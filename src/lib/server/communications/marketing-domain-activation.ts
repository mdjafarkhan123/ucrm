import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { listCloudflareDnsRecords, resolveCloudflareZone } from './cloudflare-dns';
import {
	assertSubdomainNotOccupied,
	assertUnderSubdomain,
	EmailDomainActivationError,
	reconcileRecord,
	type ExpectedRecord
} from './dns-reconcile';
import {
	associateSesTenantResource,
	configurationSetExists,
	createSesConfigurationSet,
	createSesIdentity,
	createSesTenant,
	ensureSesEventDestination,
	getSesIdentity,
	getSesTenant,
	putSesIdentityMailFrom,
	sesConfigurationSetArn,
	sesIdentityArn,
	sesMailFromMxTarget,
	type SesIdentity
} from './ses';

// Managed Marketing sending-identity reconciler (M4 stage 1). Same desired-state saga shape as
// email-domain-activation.ts -- every provider step is idempotent, no database transaction is held across an
// AWS or Cloudflare call, and a Recheck safely resumes after DNS propagation or a partial provider failure.
// The owner route owns authorization, rate limiting, idempotency receipts, and the audit event.
//
// Why a separate subdomain and a separate provider from operational email
// (docs/marketing-first-release-plan.md §2):
//   - Marketing sends from news.<root> with MAIL FROM bounce.news.<root>, on Amazon SES. Operational quotes,
//     invoices, and receipts keep mail.<root> on Brevo. Splitting the bulk stream off the transactional one is
//     the standard deliverability practice: campaign complaints must not be able to damage the reputation a
//     contractor's invoices depend on.
//   - The row is purpose='marketing_sending', so every existing purpose='sending' query keeps excluding it.
//   - Only records under news.<root> are ever written. The root, mail.<root>, and reply.<root> are untouched.

const MARKETING_SUBDOMAIN_LABEL = 'news';
const MAIL_FROM_LABEL = 'bounce';

// SES publishes the sending domain's SPF through its own include. The MAIL FROM subdomain is a UCRM-owned
// name that serves nothing else, so a strict-ish `~all` is safe and is what AWS documents.
const MAIL_FROM_SPF_VALUE = 'v=spf1 include:amazonses.com ~all';
const MAIL_FROM_MX_PRIORITY = 10;

type DnsStatus = 'unchecked' | 'pending' | 'passing' | 'failing';

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
};

type OwnerClient = SupabaseClient<Database>;

// ---------------------------------------------------------------------------------------------------
// Derivation
// ---------------------------------------------------------------------------------------------------

const ROOT_DOMAIN_PATTERN =
	/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;

function deriveMarketingDomains(rootDomain: string): {
	root: string;
	marketing: string;
	mailFrom: string;
} {
	const root = rootDomain.trim().toLowerCase();
	if (!ROOT_DOMAIN_PATTERN.test(root)) {
		throw new EmailDomainActivationError(
			'The root domain is not a valid domain name.',
			'invalid_root_domain',
			false
		);
	}
	const marketing = `${MARKETING_SUBDOMAIN_LABEL}.${root}`;
	// The MAIL FROM name lives UNDER the marketing subdomain, so the whole activation writes inside one name
	// UCRM owns and assertUnderSubdomain can guard every record with a single suffix.
	return { root, marketing, mailFrom: `${MAIL_FROM_LABEL}.${marketing}` };
}

/**
 * The SES tenant and configuration set names for an organization. Both are global within the AWS account and
 * both are derived, never stored-then-guessed, so a half-finished run re-derives exactly the same names.
 * Matches communication_ses_tenants' `^[A-Za-z0-9_-]{1,64}$` check (a UUID is hex and hyphens).
 */
function sesResourceNames(organizationId: string): {
	tenantName: string;
	configurationSetName: string;
} {
	return {
		tenantName: `ucrm-org-${organizationId}`,
		configurationSetName: `ucrm-marketing-${organizationId}`
	};
}

// ---------------------------------------------------------------------------------------------------
// Status mapping
// ---------------------------------------------------------------------------------------------------

/**
 * Maps an SES verification status onto the four-state health value this table already uses everywhere.
 * TEMPORARY_FAILURE is 'pending', not 'failing': SES retries these on its own for up to 72 hours, so calling
 * it a failure would make a healthy activation look broken while DNS is still settling.
 */
function sesStatusToDns(status: string | null | undefined): DnsStatus {
	switch ((status ?? '').toUpperCase()) {
		case 'SUCCESS':
			return 'passing';
		case 'PENDING':
		case 'TEMPORARY_FAILURE':
			return 'pending';
		case 'FAILED':
			return 'failing';
		default:
			return 'unchecked';
	}
}

// ---------------------------------------------------------------------------------------------------
// SES reconciliation
// ---------------------------------------------------------------------------------------------------

/**
 * Brings the organization's SES tenant, configuration set, and event destination to their desired state and
 * records them. A tenant is per organization rather than per domain because it outlives a marketing domain
 * replacement, and it is what keeps one contractor's reputation enforcement and suppression off another's.
 */
async function reconcileSesTenant(
	client: OwnerClient,
	organizationId: string
): Promise<{ tenantName: string; tenantArn: string | null; configurationSetName: string }> {
	const { tenantName, configurationSetName } = sesResourceNames(organizationId);

	const existingTenant = await getSesTenant(tenantName);
	const tenant = existingTenant ?? (await createSesTenant(tenantName));

	if (!(await configurationSetExists(configurationSetName))) {
		await createSesConfigurationSet(configurationSetName);
	}
	// Without this the dispatcher would send successfully and never learn what happened to the message.
	const eventDestinationReady = await ensureSesEventDestination(configurationSetName);

	const now = new Date().toISOString();
	const { error } = await client.from('communication_ses_tenants').upsert(
		{
			organization_id: organizationId,
			tenant_name: tenantName,
			tenant_arn: tenant.tenantArn,
			configuration_set_name: configurationSetName,
			event_destination_ready: eventDestinationReady,
			updated_at: now
		},
		{ onConflict: 'organization_id' }
	);
	if (error) throw error;

	return { tenantName, tenantArn: tenant.tenantArn, configurationSetName };
}

/** Reuses the SES domain identity or creates it with Easy DKIM, then reads back its DKIM tokens. */
async function reconcileSesIdentity(marketing: string): Promise<SesIdentity> {
	const existing = await getSesIdentity(marketing);
	if (existing) return existing;

	await createSesIdentity(marketing);
	const created = await getSesIdentity(marketing);
	if (!created) {
		throw new EmailDomainActivationError(
			'Amazon SES accepted the sending identity but did not return it. Try the check again.',
			'ses_identity_not_readable',
			true
		);
	}
	return created;
}

/**
 * The records the contractor's zone must serve: three Easy DKIM CNAMEs under the marketing subdomain, and the
 * MX plus SPF TXT that give the custom MAIL FROM subdomain its own bounce path and SPF alignment.
 */
function expectedMarketingRecords(
	identity: SesIdentity,
	marketing: string,
	mailFrom: string
): ExpectedRecord[] {
	const dkim: ExpectedRecord[] = identity.dkimTokens.map((token) => ({
		type: 'CNAME',
		name: `${token}._domainkey.${marketing}`,
		content: `${token}.dkim.amazonses.com`
	}));

	return [
		...dkim,
		{
			type: 'MX',
			name: mailFrom,
			content: sesMailFromMxTarget(),
			priority: MAIL_FROM_MX_PRIORITY
		},
		{ type: 'TXT', name: mailFrom, content: MAIL_FROM_SPF_VALUE }
	];
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
	const existingId = await findExistingMarketingDomainId(
		input.client,
		input.organizationId,
		marketing
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
	const previouslyVerified = Boolean(history.verifiedAt) || history.lifecycleState === 'unhealthy';
	const lifecycleState: MarketingDomainSummary['lifecycle_state'] = ready
		? 'verified'
		: previouslyVerified
			? 'unhealthy'
			: 'pending_dns';

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
		dns_records: expected.map((record) => ({
			type: record.type,
			host_name: record.name,
			value: record.content,
			...(record.priority != null ? { priority: record.priority } : {})
		})) as unknown as Database['public']['Tables']['communication_email_domains']['Insert']['dns_records'],
		lifecycle_state: lifecycleState,
		last_checked_at: now,
		// First verification stamps the clock; a later healthy recheck keeps the original date, and a domain
		// that has fallen unhealthy keeps it too, so "verified since" stays honest.
		verified_at: ready ? (history.verifiedAt ?? now) : history.verifiedAt,
		updated_at: now
	};

	const domainId = await upsertMarketingDomainRow(client, existingId, row);

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
		}
	};
}

// ---------------------------------------------------------------------------------------------------
// Row helpers
// ---------------------------------------------------------------------------------------------------

/**
 * The live row for this marketing domain, or null. communication_email_domains_live_claim_idx allows one live
 * row per domain_name across the whole platform, so a name already claimed elsewhere is a conflict a human
 * resolves rather than something activation may take over.
 */
async function findExistingMarketingDomainId(
	client: OwnerClient,
	organizationId: string,
	marketing: string
): Promise<string | null> {
	const { data, error } = await client
		.from('communication_email_domains')
		.select('id, organization_id, purpose')
		.eq('domain_name', marketing)
		.neq('lifecycle_state', 'removed')
		.maybeSingle();
	if (error) throw error;
	if (!data) return null;
	if (data.organization_id !== organizationId || data.purpose !== 'marketing_sending') {
		throw new EmailDomainActivationError(
			`${marketing} is already claimed by another organization or purpose.`,
			'domain_already_claimed',
			false
		);
	}
	return data.id;
}

/**
 * What an existing row already recorded. A domain that has verified before turns a later failed check into
 * 'unhealthy' rather than back into 'pending_dns', and keeps its original verified_at.
 */
async function readDomainHistory(
	client: OwnerClient,
	existingId: string | null
): Promise<{ verifiedAt: string | null; lifecycleState: string | null }> {
	if (!existingId) return { verifiedAt: null, lifecycleState: null };
	const { data, error } = await client
		.from('communication_email_domains')
		.select('verified_at, lifecycle_state')
		.eq('id', existingId)
		.maybeSingle();
	if (error) throw error;
	return { verifiedAt: data?.verified_at ?? null, lifecycleState: data?.lifecycle_state ?? null };
}

/** Inserts a new domain row or updates the existing one, returning its id. Never inside a transaction. */
async function upsertMarketingDomainRow(
	client: OwnerClient,
	existingId: string | null,
	row: Database['public']['Tables']['communication_email_domains']['Insert']
): Promise<string> {
	if (existingId) {
		const { error } = await client
			.from('communication_email_domains')
			.update(row)
			.eq('id', existingId);
		if (error) throw error;
		return existingId;
	}
	const { data, error } = await client
		.from('communication_email_domains')
		.insert(row)
		.select('id')
		.single();
	if (error) throw error;
	return data.id;
}
