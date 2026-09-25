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
	ensureSesEventDestination,
	getSesIdentity,
	putSesIdentityMailFrom,
	sesConfigurationSetArn,
	sesIdentityArn,
	sesInboundMxTarget,
	sesMailFromMxTarget
} from './ses';
import {
	ensureSesConfigurationSet,
	findExistingDomainId,
	nextLifecycleState,
	normalizeRootDomain,
	operationalConfigurationSetName,
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

export { EmailDomainActivationError } from './dns-reconcile';

// Managed operational ("everyday email") domain activation on Amazon SES. A desired-state saga like the
// Marketing reconciler: every provider step is idempotent, no database transaction is held across an AWS or
// Cloudflare call, and a Recheck safely resumes after DNS propagation or a partial provider failure. The owner
// route owns authorization, rate limiting, idempotency receipts, and the audit event.
//
// Safety rules (docs/contractor-email-contract.md "Domain provisioning and sender identity"):
//   - Sending and receiving live on INDEPENDENTLY derived subdomains, mail.<root> and reply.<root>. The custom
//     MAIL FROM is bounce.mail.<root>, which neither sends nor receives.
//   - Only records under mail.<root> and reply.<root> are ever written. Root MX, root mailbox authentication,
//     and any unexpected occupied subdomain record are never overwritten.
//
// Receiving is prepared, not switched. This run creates and verifies the reply.<root> SES identity (SES
// requires a verified domain before it will receive for it), but it leaves reply.<root>'s MX and its receiving
// row alone. Moving the MX before a receipt rule exists would drop customer replies, so the MX, the row, and
// the receipt rule change together in the reply-ingestion step.

const SENDING_LABEL = 'mail';
const RECEIVING_LABEL = 'reply';
const MAIL_FROM_LABEL = 'bounce';

// Brevo's inbound MX targets. A reply subdomain still served by Brevo during the move to SES is expected, not
// occupied. Removed with the rest of the Brevo contractor paths at cutover.
const BREVO_INBOUND_MX_TARGETS = ['inbound1.sendinblue.com', 'inbound2.sendinblue.com'];

export type OperationalSendingSummary = {
	domain_id: string;
	domain_name: string;
	mail_from_domain: string;
	purpose: 'sending';
	lifecycle_state: 'pending_dns' | 'verified' | 'unhealthy';
	provider_verified: boolean;
	provider_authenticated: boolean;
	ownership_status: DnsStatus;
	dkim_status: DnsStatus;
	spf_status: DnsStatus;
	records_written: number;
	tenant_name: string;
	configuration_set_name: string;
	event_destination_ready: boolean;
};

export type OperationalReceivingSummary = {
	domain_name: string;
	// The SES identity's verification: with Easy DKIM the CNAMEs are the ownership proof.
	ses_identity_status: DnsStatus;
	records_written: number;
	// The receiving row as it stands. Null until reply ingestion on SES creates or switches it.
	domain_id: string | null;
	lifecycle_state: string | null;
	inbound_mx_status: DnsStatus | null;
};

export type OperationalActivationResult = {
	root_domain: string;
	zone_id: string;
	sending: OperationalSendingSummary;
	receiving: OperationalReceivingSummary;
};

function deriveOperationalDomains(rootDomain: string) {
	const root = normalizeRootDomain(rootDomain);
	// Derived independently: reply.<root> is never a function of mail.<root>.
	const sending = `${SENDING_LABEL}.${root}`;
	return {
		root,
		sending,
		receiving: `${RECEIVING_LABEL}.${root}`,
		mailFrom: `${MAIL_FROM_LABEL}.${sending}`
	};
}

export async function activateOperationalDomain(input: {
	client: OwnerClient;
	organizationId: string;
	rootDomain: string;
}): Promise<OperationalActivationResult> {
	return reconcileOperationalDomain({
		client: input.client,
		organizationId: input.organizationId,
		...deriveOperationalDomains(input.rootDomain)
	});
}

/**
 * Re-runs the same reconciliation for a sending row. Everything is idempotent, so a Recheck is simply another
 * pass: it re-reads SES, repairs any record that drifted, and re-derives the health values.
 */
export async function recheckOperationalDomain(input: {
	client: OwnerClient;
	organizationId: string;
	domainId: string;
}): Promise<OperationalActivationResult> {
	const { data, error } = await input.client
		.from('communication_email_domains')
		.select('id, domain_name, dns_zone, purpose, provider')
		.eq('organization_id', input.organizationId)
		.eq('id', input.domainId)
		.neq('lifecycle_state', 'removed')
		.maybeSingle();
	if (error) throw error;
	if (!data || data.purpose !== 'sending' || data.provider !== 'ses') {
		throw new EmailDomainActivationError(
			'Everyday email sending domain on Amazon SES was not found.',
			'operational_domain_not_found',
			false
		);
	}
	if (!data.dns_zone) {
		throw new EmailDomainActivationError(
			'This sending domain has no recorded root domain. Run Set up again.',
			'operational_domain_missing_root',
			false
		);
	}

	const domains = deriveOperationalDomains(data.dns_zone);
	if (domains.sending !== data.domain_name) {
		throw new EmailDomainActivationError(
			'This sending domain does not match its recorded root domain.',
			'operational_domain_mismatch',
			false
		);
	}

	return reconcileOperationalDomain({
		client: input.client,
		organizationId: input.organizationId,
		...domains
	});
}

async function reconcileOperationalDomain(input: {
	client: OwnerClient;
	organizationId: string;
	root: string;
	sending: string;
	receiving: string;
	mailFrom: string;
}): Promise<OperationalActivationResult> {
	const { client, organizationId, root, sending, receiving, mailFrom } = input;

	// Claim checks first, so a name owned by another organization stops the run before any provider call.
	const sendingId = await findExistingDomainId(client, organizationId, sending, 'sending');
	const receivingId = await findExistingDomainId(client, organizationId, receiving, 'receiving');

	// The managed zone that CONTAINS the root, by longest suffix.
	const { id: zoneId } = await resolveCloudflareZone(root);

	const tenant = await reconcileSesTenant(client, organizationId);
	const configurationSetName = operationalConfigurationSetName(organizationId);
	await ensureSesConfigurationSet(configurationSetName);
	// Without this the operational dispatcher would send successfully and never learn what happened to it --
	// this call already exists and is already reused as-is for Marketing's configuration set.
	const eventDestinationReady = await ensureSesEventDestination(configurationSetName);

	const sendingIdentity = await reconcileSesIdentity(sending);
	const receivingIdentity = await reconcileSesIdentity(receiving);

	// Point the identity at the custom MAIL FROM before writing DNS, so SES is already watching for the records
	// when they appear. BehaviorOnMxFailure falls back to amazonses.com meanwhile, so nothing bounces while the
	// records propagate.
	if (sendingIdentity.mailFromDomain !== mailFrom) {
		await putSesIdentityMailFrom(sending, mailFrom);
	}

	const sendingRecords = [
		...sesDkimRecords(sendingIdentity, sending),
		...sesMailFromRecords(mailFrom)
	];
	const receivingRecords = sesDkimRecords(receivingIdentity, receiving);
	assertUnderSubdomain(sendingRecords, sending);
	assertUnderSubdomain(receivingRecords, receiving);

	// Occupancy: none of the three names may already serve another service. The provider's own mail hosts are
	// allowed so a re-run, a Recheck, and a domain still receiving through Brevo are all safe.
	assertSubdomainNotOccupied(sending, await listCloudflareDnsRecords(zoneId, sending), []);
	assertSubdomainNotOccupied(mailFrom, await listCloudflareDnsRecords(zoneId, mailFrom), [
		sesMailFromMxTarget()
	]);
	assertSubdomainNotOccupied(receiving, await listCloudflareDnsRecords(zoneId, receiving), [
		sesInboundMxTarget(),
		...BREVO_INBOUND_MX_TARGETS
	]);

	const sendingWritten = await writeRecords(zoneId, sendingRecords);
	const receivingWritten = await writeRecords(zoneId, receivingRecords);

	// Authorize the tenant to send from this identity with this configuration set. Runs on every pass rather
	// than only on the run that created them, so a Recheck repairs a missing association.
	await associateSesTenantResource(tenant.tenantName, sesIdentityArn(sending));
	await associateSesTenantResource(tenant.tenantName, sesConfigurationSetArn(configurationSetName));

	// Read the identities back after the records are in place: SES re-checks on its own schedule, so this
	// reports the truth at this moment and a later Recheck picks up the change.
	const settled = (await getSesIdentity(sending)) ?? sendingIdentity;
	const settledReceiving = (await getSesIdentity(receiving)) ?? receivingIdentity;

	// With Easy DKIM the three CNAMEs ARE the proof of domain control, so ownership and DKIM share one status.
	const dkimStatus = sesStatusToDns(settled.dkimStatus);
	const spfStatus = sesStatusToDns(settled.mailFromStatus);
	const providerVerified = settled.verifiedForSending;
	const providerAuthenticated = settled.dkimSigningEnabled && dkimStatus === 'passing';
	// The contract gates sending on SES verification plus passing Easy DKIM. MAIL FROM is reported but not
	// required: until it resolves, SES falls back to its own MAIL FROM and mail still flows.
	const ready = providerVerified && providerAuthenticated;

	const now = new Date().toISOString();
	const history = await readDomainHistory(client, sendingId);
	const lifecycleState = nextLifecycleState(ready, history);

	const domainId = await upsertDomainRow(client, sendingId, {
		organization_id: organizationId,
		purpose: 'sending',
		domain_name: sending,
		dns_zone: root,
		provider: 'ses',
		// SES has no opaque domain id: the identity IS the domain name, so the ARN is the stable handle worth
		// storing for sending and for cleanup.
		provider_domain_id: sesIdentityArn(sending),
		provider_verified: providerVerified,
		provider_authenticated: providerAuthenticated,
		ownership_status: dkimStatus,
		dkim_status: dkimStatus,
		spf_status: spfStatus,
		// inbound_mx_status stays 'unchecked' on a sending row (purpose_health_check).
		inbound_mx_status: 'unchecked',
		dns_records: toStoredDnsRecords(sendingRecords),
		lifecycle_state: lifecycleState,
		last_checked_at: now,
		// First verification stamps the clock; a later recheck keeps the original date, so warm-up and
		// "verified since" stay honest.
		verified_at: ready ? (history.verifiedAt ?? now) : history.verifiedAt,
		updated_at: now
	});

	return {
		root_domain: root,
		zone_id: zoneId,
		sending: {
			domain_id: domainId,
			domain_name: sending,
			mail_from_domain: mailFrom,
			purpose: 'sending',
			lifecycle_state: lifecycleState,
			provider_verified: providerVerified,
			provider_authenticated: providerAuthenticated,
			ownership_status: dkimStatus,
			dkim_status: dkimStatus,
			spf_status: spfStatus,
			records_written: sendingWritten,
			tenant_name: tenant.tenantName,
			configuration_set_name: configurationSetName,
			event_destination_ready: eventDestinationReady
		},
		receiving: {
			domain_name: receiving,
			ses_identity_status: sesStatusToDns(settledReceiving.dkimStatus),
			records_written: receivingWritten,
			...(await readReceivingRow(client, receivingId))
		}
	};
}

async function writeRecords(zoneId: string, records: ExpectedRecord[]): Promise<number> {
	let written = 0;
	for (const record of records) {
		if ((await reconcileRecord(zoneId, record)) !== 'unchanged') written += 1;
	}
	return written;
}

async function readReceivingRow(
	client: OwnerClient,
	receivingId: string | null
): Promise<
	Pick<OperationalReceivingSummary, 'domain_id' | 'lifecycle_state' | 'inbound_mx_status'>
> {
	if (!receivingId) return { domain_id: null, lifecycle_state: null, inbound_mx_status: null };
	const { data, error } = await client
		.from('communication_email_domains')
		.select('lifecycle_state, inbound_mx_status')
		.eq('id', receivingId)
		.maybeSingle();
	if (error) throw error;
	return {
		domain_id: receivingId,
		lifecycle_state: data?.lifecycle_state ?? null,
		inbound_mx_status: (data?.inbound_mx_status as DnsStatus | undefined) ?? null
	};
}
