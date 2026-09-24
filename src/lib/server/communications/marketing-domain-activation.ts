import { reconcileClickDomain, type ClickDomainSummary } from './branded-click-domain';
import { listCloudflareDnsRecords, resolveCloudflareZone } from './cloudflare-dns';
import {
	assertSubdomainNotOccupied,
	assertUnderSubdomain,
	EmailDomainActivationError,
	reconcileRecord
} from './dns-reconcile';
import {
	associateSesTenantResource,
	getSesIdentity,
	putSesIdentityMailFrom,
	sesConfigurationSetArn,
	sesIdentityArn,
	sesMailFromMxTarget,
	type SesIdentity
} from './ses';
import {
	findExistingDomainId,
	nextLifecycleState,
	normalizeRootDomain,
	readDomainHistory,
	reconcileSesIdentity,
	reconcileSesTenant,
	sesDkimRecords,
	sesMailFromRecords,
	sesStatusToDns,
	toStoredDnsRecords,
	upsertDomainRow,
	type DnsStatus,
	type OwnerClient
} from './ses-domain-identity';

// Managed Marketing sending-identity reconciler (M4 stage 1). Same desired-state saga shape as
// operational-domain-activation.ts, and the SES tenant, identity, and row rules are shared with it through
// ses-domain-identity.ts -- every provider step is idempotent, no database transaction is held across an
// AWS or Cloudflare call, and a Recheck safely resumes after DNS propagation or a partial provider failure.
// The owner route owns authorization, rate limiting, idempotency receipts, and the audit event.
//
// Why a separate subdomain and configuration set from operational email
// (docs/marketing-first-release-plan.md §2):
//   - Marketing sends from news.<root> with MAIL FROM bounce.news.<root>. Operational quotes, invoices, and
//     receipts send from mail.<root> through their own configuration set. Splitting the bulk stream off the transactional one is
//     the standard deliverability practice: campaign complaints must not be able to damage the reputation a
//     contractor's invoices depend on.
//   - The row is purpose='marketing_sending', so every existing purpose='sending' query keeps excluding it.
//   - Only records under news.<root> are ever written. The root, mail.<root>, and reply.<root> are untouched.

const MARKETING_SUBDOMAIN_LABEL = 'news';
const MAIL_FROM_LABEL = 'bounce';

export type MarketingDomainSummary = {
	domain_id: string;
	domain_name: string;
	mail_from_domain: string;
	purpose: 'marketing_sending';
	lifecycle_state: 'pending_dns' | 'verified' | 'unhealthy';
	provider_verified: boolean;
	provider_authenticated: boolean;
	ownership_status: DnsStatus;
	dkim_status: DnsStatus;
	spf_status: DnsStatus;
	records_written: number;
	tenant_name: string;
	configuration_set_name: string;
};

export type MarketingActivationResult = {
	root_domain: string;
	zone_id: string;
	marketing: MarketingDomainSummary;
	click: ClickDomainSummary;
};

// ---------------------------------------------------------------------------------------------------
// Derivation
// ---------------------------------------------------------------------------------------------------

function deriveMarketingDomains(rootDomain: string): {
	root: string;
	marketing: string;
	mailFrom: string;
} {
	const root = normalizeRootDomain(rootDomain);
	const marketing = `${MARKETING_SUBDOMAIN_LABEL}.${root}`;
	// The MAIL FROM name lives UNDER the marketing subdomain, so the whole activation writes inside one name
	// UCRM owns and assertUnderSubdomain can guard every record with a single suffix.
	return { root, marketing, mailFrom: `${MAIL_FROM_LABEL}.${marketing}` };
}

/**
 * The records the contractor's zone must serve: three Easy DKIM CNAMEs under the marketing subdomain, and the
 * MX plus SPF TXT that give the custom MAIL FROM subdomain its own bounce path and SPF alignment.
 */
function expectedMarketingRecords(identity: SesIdentity, marketing: string, mailFrom: string) {
	return [...sesDkimRecords(identity, marketing), ...sesMailFromRecords(mailFrom)];
}

// ---------------------------------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------------------------------

export async function activateMarketingDomain(input: {
	client: OwnerClient;
	organizationId: string;
	rootDomain: string;
}): Promise<MarketingActivationResult> {
	const { root, marketing, mailFrom } = deriveMarketingDomains(input.rootDomain);
	const existingId = await findExistingDomainId(
		input.client,
		input.organizationId,
		marketing,
		'marketing_sending'
	);
	return reconcileMarketingDomain({
		client: input.client,
		organizationId: input.organizationId,
		root,
		marketing,
		mailFrom,
		existingId
	});
}

/**
 * Re-runs the same reconciliation for a domain that already has a row. Everything is idempotent, so a Recheck
 * is simply another pass: it re-reads SES, repairs any record that drifted, and re-derives the health values.
 */
export async function recheckMarketingDomain(input: {
	client: OwnerClient;
	organizationId: string;
	domainId: string;
}): Promise<MarketingActivationResult> {
	const { data, error } = await input.client
		.from('communication_email_domains')
		.select('id, domain_name, dns_zone, purpose, lifecycle_state')
		.eq('organization_id', input.organizationId)
		.eq('id', input.domainId)
		.neq('lifecycle_state', 'removed')
		.maybeSingle();
	if (error) throw error;
	if (!data || data.purpose !== 'marketing_sending') {
		throw new EmailDomainActivationError(
			'Marketing sending domain was not found.',
			'marketing_domain_not_found',
			false
		);
	}

	// dns_zone holds the root this domain was derived from, so the recheck never has to parse the subdomain
	// back apart. A row written before dns_zone existed cannot be rechecked; the owner re-runs Activate.
	if (!data.dns_zone) {
		throw new EmailDomainActivationError(
			'This marketing domain has no recorded root domain. Run Activate again.',
			'marketing_domain_missing_root',
			false
		);
	}

	const { root, marketing, mailFrom } = deriveMarketingDomains(data.dns_zone);
	if (marketing !== data.domain_name) {
		throw new EmailDomainActivationError(
			'This marketing domain does not match its recorded root domain.',
			'marketing_domain_mismatch',
			false
		);
	}

	return reconcileMarketingDomain({
		client: input.client,
		organizationId: input.organizationId,
		root,
		marketing,
		mailFrom,
		existingId: data.id
	});
}

async function reconcileMarketingDomain(input: {
	client: OwnerClient;
	organizationId: string;
	root: string;
	marketing: string;
	mailFrom: string;
	existingId: string | null;
}): Promise<MarketingActivationResult> {
	const { client, organizationId, root, marketing, mailFrom, existingId } = input;

	// The managed zone that CONTAINS the root, by longest suffix.
	const { id: zoneId } = await resolveCloudflareZone(root);

	const tenant = await reconcileSesTenant(client, organizationId);
	const identity = await reconcileSesIdentity(marketing);

	// Point the identity at the custom MAIL FROM before writing DNS, so SES is already watching for the
	// records when they appear. BehaviorOnMxFailure falls back to amazonses.com meanwhile, so nothing bounces
	// while the records propagate.
	if (identity.mailFromDomain !== mailFrom) {
		await putSesIdentityMailFrom(marketing, mailFrom);
	}

	const expected = expectedMarketingRecords(identity, marketing, mailFrom);
	assertUnderSubdomain(expected, marketing);

	// Occupancy: neither the marketing subdomain apex nor the bounce name may already serve another service.
	// SES's own feedback host is allowed at the bounce name so a re-run and a Recheck are safe.
	assertSubdomainNotOccupied(marketing, await listCloudflareDnsRecords(zoneId, marketing), []);
	assertSubdomainNotOccupied(mailFrom, await listCloudflareDnsRecords(zoneId, mailFrom), [
		sesMailFromMxTarget()
	]);

	let recordsWritten = 0;
	for (const record of expected) {
		const outcome = await reconcileRecord(zoneId, record);
		if (outcome !== 'unchanged') recordsWritten += 1;
	}

	// Authorize the tenant to use both resources. A tenant associated with neither cannot send at all, so this
	// runs on every pass rather than only on the run that created them.
	await associateSesTenantResource(tenant.tenantName, sesIdentityArn(marketing));
	await associateSesTenantResource(
		tenant.tenantName,
		sesConfigurationSetArn(tenant.configurationSetName)
	);

	// Read the identity back after the records are in place: SES re-checks on its own schedule, so this
	// reports the truth at this moment and a later Recheck picks up the change.
	const settled = (await getSesIdentity(marketing)) ?? identity;

	// With Easy DKIM, the three CNAMEs ARE the proof of domain control -- SES issues no separate ownership
	// token -- so ownership and DKIM share one status rather than inventing a second, always-identical one.
	const dkimStatus = sesStatusToDns(settled.dkimStatus);
	const ownershipStatus = dkimStatus;
	const spfStatus = sesStatusToDns(settled.mailFromStatus);
	const providerVerified = settled.verifiedForSending;
	const providerAuthenticated = settled.dkimSigningEnabled && dkimStatus === 'passing';

	const ready =
		providerVerified &&
		providerAuthenticated &&
		ownershipStatus === 'passing' &&
		dkimStatus === 'passing' &&
		spfStatus === 'passing' &&
		settled.mailFromDomain === mailFrom;

	const now = new Date().toISOString();
	const history = await readDomainHistory(client, existingId);
	const lifecycleState = nextLifecycleState(ready, history);

	const row = {
		organization_id: organizationId,
		purpose: 'marketing_sending' as const,
		domain_name: marketing,
		dns_zone: root,
		provider: 'ses' as const,
		// SES has no opaque domain id: the identity IS the domain name, so the ARN is the stable handle worth
		// storing for the dispatcher and for cleanup.
		provider_domain_id: sesIdentityArn(marketing),
		provider_verified: providerVerified,
		provider_authenticated: providerAuthenticated,
		ownership_status: ownershipStatus,
		dkim_status: dkimStatus,
		spf_status: spfStatus,
		// No DMARC record is written for the marketing subdomain in this release, and a marketing row keeps
		// inbound_mx_status 'unchecked' (communication_email_domains_purpose_health_check).
		dmarc_status: 'unchecked' as const,
		inbound_mx_status: 'unchecked' as const,
		dns_records: toStoredDnsRecords(expected),
		lifecycle_state: lifecycleState,
		last_checked_at: now,
		// First verification stamps the clock; a later healthy recheck keeps the original date, and a domain
		// that has fallen unhealthy keeps it too, so "verified since" stays honest.
		verified_at: ready ? (history.verifiedAt ?? now) : history.verifiedAt,
		updated_at: now
	};

	const domainId = await upsertDomainRow(client, existingId, row);

	// Branded click links (M6d) come last: they need a verified sending identity, and the step records its own
	// failures on the row rather than throwing, so it can never fail the sending activation above.
	const click = await reconcileClickDomain({ client, organizationId, domainId, zoneId });

	return {
		root_domain: root,
		zone_id: zoneId,
		marketing: {
			domain_id: domainId,
			domain_name: marketing,
			mail_from_domain: mailFrom,
			purpose: 'marketing_sending',
			lifecycle_state: lifecycleState,
			provider_verified: providerVerified,
			provider_authenticated: providerAuthenticated,
			ownership_status: ownershipStatus,
			dkim_status: dkimStatus,
			spf_status: spfStatus,
			records_written: recordsWritten,
			tenant_name: tenant.tenantName,
			configuration_set_name: tenant.configurationSetName
		},
		click
	};
}
