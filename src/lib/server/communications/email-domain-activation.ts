import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	authenticateBrevoDomain,
	BrevoManagementError,
	createBrevoDomain,
	createBrevoInboundWebhook,
	getBrevoDomain,
	listBrevoDomains,
	listBrevoInboundWebhooks,
	type BrevoDnsRecord
} from './brevo';
import {
	createCloudflareDnsRecord,
	listCloudflareDnsRecords,
	resolveCloudflareZone,
	updateCloudflareDnsRecord,
	type CloudflareDnsRecord,
	type CloudflareRecordInput
} from './cloudflare-dns';

// Managed email-domain activation reconciler (A1-D). This is a desired-state saga: every provider step is
// idempotent, no database transaction is ever held across a Brevo or Cloudflare call, and a Recheck safely
// resumes after DNS propagation or a partial provider failure. The owner route owns authorization, rate
// limiting, idempotency receipts, and the audit event; this module owns the reconciliation itself.
//
// Safety rules (docs/research/cloudflare-dns-mailbox-preservation-and-brevo-subdomains.md,
// docs/contractor-email-contract.md):
//   - Sending and receiving live on INDEPENDENTLY derived subdomains: mail.<root> and reply.<root>. The
//     receiving name is never derived from the sending name.
//   - Only records UCRM owns, under those two subdomains, are ever written. Root MX, root mailbox
//     authentication, and any unexpected occupied subdomain record are never overwritten -- an occupied or
//     conflicting mail./reply. name stops the run for owner review.
//   - Every mail/verification record is DNS-only (never proxied). Record values are discovered from Brevo at
//     activation time; only the two inbound MX targets are the documented Brevo constants.

// Brevo's inbound-parse receiving MX targets. Fixed, documented values (priority 10 then 20) -- the only
// records not discovered from Brevo at runtime. docs/research/brevo-return-path-production-patterns.md
const BREVO_INBOUND_MX = [
	{ target: 'inbound1.sendinblue.com', priority: 10 },
	{ target: 'inbound2.sendinblue.com', priority: 20 }
] as const;

// A managed record type set. Anything else already living at a managed subdomain apex means the name is in
// use by another service, so the reconciler refuses rather than guessing.
const MANAGED_RECORD_TYPES = new Set(['TXT', 'CNAME', 'MX']);

export class EmailDomainActivationError extends Error {
	constructor(
		message: string,
		public readonly code: string,
		// retryable: an unknown/ambiguous provider outcome the owner can safely re-run. A conflict
		// (occupied name) is NOT retryable -- it needs a human decision.
		public readonly retryable: boolean
	) {
		super(message);
		this.name = 'EmailDomainActivationError';
	}
}

type DnsStatus = 'unchecked' | 'pending' | 'passing' | 'failing';

export type ActivationDomainSummary = {
	domain_id: string;
	domain_name: string;
	purpose: 'sending' | 'receiving';
	lifecycle_state: string;
	provider_verified: boolean;
	provider_authenticated: boolean;
	ownership_status: DnsStatus;
	dkim_status: DnsStatus;
	inbound_mx_status: DnsStatus;
	records_written: number;
};

export type ActivationResult = {
	root_domain: string;
	zone_id: string;
	sending: ActivationDomainSummary;
	// provider_inbound_webhook_id is null while the receiving domain is not yet active in Brevo: the DNS is in
	// place but Brevo has not verified it, so the webhook cannot be attached until a later Recheck.
	receiving: ActivationDomainSummary & { provider_inbound_webhook_id: string | null };
};

type OwnerClient = SupabaseClient<Database>;

// ---------------------------------------------------------------------------------------------------
// Derivation and validation
// ---------------------------------------------------------------------------------------------------

const ROOT_DOMAIN_PATTERN =
	/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;

function deriveDomains(rootDomain: string): { sending: string; receiving: string } {
	const root = rootDomain.trim().toLowerCase();
	if (!ROOT_DOMAIN_PATTERN.test(root)) {
		throw new EmailDomainActivationError(
			'The root domain is not a valid domain name.',
			'invalid_root_domain',
			false
		);
	}
	// Derived INDEPENDENTLY. reply.<root> is never a function of mail.<root>.
	return { sending: `mail.${root}`, receiving: `reply.${root}` };
}

// ---------------------------------------------------------------------------------------------------
// Expected-record model. Each expected record is keyed by (type, name); the reconciler brings exactly
// these to their desired content and writes nothing else.
// ---------------------------------------------------------------------------------------------------

type ExpectedRecord = {
	type: string;
	name: string;
	content: string;
	priority?: number;
};

function normalizeName(name: string): string {
	return name.trim().toLowerCase().replace(/\.$/, '');
}

/**
 * Fully-qualifies a Brevo-issued host name against the managed domain and its Cloudflare zone apex.
 *
 * Brevo does NOT return fully-qualified names: it shortens each host name relative to the Cloudflare zone apex
 * (`mail.test` for the domain `mail.test.acme.com` in the `acme.com` zone), EXCEPT DKIM (`_domainkey`) records,
 * which it shortens relative to the sending/receiving DOMAIN (`brevo1._domainkey`). DKIM must be domain-relative
 * because `mail.<root>` and `reply.<root>` share one zone, so a zone-relative `brevo1._domainkey` would collide
 * between the two. We therefore qualify to the zone first; if that lands outside the managed subdomain, the name
 * was domain-relative, so we qualify to the domain instead. `assertUnderSubdomain` is still the final guard.
 */
function qualifyBrevoHostName(hostName: string, domain: string, zoneName: string): string {
	const host = normalizeName(hostName);
	// Already fully-qualified under the domain or its zone apex.
	if (host === domain || host.endsWith(`.${domain}`)) return host;
	if (host === zoneName || host.endsWith(`.${zoneName}`)) return host;

	const zoneQualified = `${host}.${zoneName}`;
	if (zoneQualified === domain || zoneQualified.endsWith(`.${domain}`)) return zoneQualified;
	return `${host}.${domain}`;
}

function brevoRecordToExpected(
	record: BrevoDnsRecord,
	domain: string,
	zoneName: string
): ExpectedRecord {
	return {
		type: record.type.trim().toUpperCase(),
		name: qualifyBrevoHostName(record.host_name, domain, zoneName),
		content: record.value.trim()
	};
}

/**
 * Every Brevo-issued record for a managed subdomain must live at or under that subdomain. A record whose
 * host name escapes the subdomain would mean writing outside the name UCRM controls, so the run refuses.
 */
function assertUnderSubdomain(records: ExpectedRecord[], subdomain: string): void {
	const suffix = `.${subdomain}`;
	for (const record of records) {
		if (record.name !== subdomain && !record.name.endsWith(suffix)) {
			throw new EmailDomainActivationError(
				`Brevo returned a record for ${record.name}, which is outside ${subdomain}. Activation will not write outside the managed subdomain.`,
				'record_outside_subdomain',
				false
			);
		}
	}
}

/**
 * Refuses a managed subdomain whose apex already serves another service. An MX that is not a Brevo inbound
 * target, or any record type UCRM does not manage, means the name is occupied and a human must decide.
 */
function assertSubdomainNotOccupied(subdomain: string, existing: CloudflareDnsRecord[]): void {
	for (const record of existing) {
		const type = record.type.trim().toUpperCase();
		if (!MANAGED_RECORD_TYPES.has(type)) {
			throw new EmailDomainActivationError(
				`${subdomain} already has a ${type} record and appears to be in use. Activation will not overwrite it.`,
				'subdomain_occupied',
				false
			);
		}
		if (type === 'MX') {
			const content = normalizeName(record.content);
			const isBrevoInbound = BREVO_INBOUND_MX.some((mx) => content === normalizeName(mx.target));
			if (!isBrevoInbound) {
				throw new EmailDomainActivationError(
					`${subdomain} already routes mail to ${record.content}. Activation will not replace an existing mail route.`,
					'subdomain_occupied',
					false
				);
			}
		}
	}
}

/**
 * Brings one expected record to its desired content in Cloudflare and reports how it settled. Reuses an
 * exact match, updates the single managed record of the same type when its content drifted, creates when
 * absent, and refuses an ambiguous name that has several conflicting records of the same type.
 */
async function reconcileRecord(
	zoneId: string,
	expected: ExpectedRecord
): Promise<'created' | 'updated' | 'unchanged'> {
	const existing = await listCloudflareDnsRecords(zoneId, expected.name);
	const sameType = existing.filter((record) => record.type.trim().toUpperCase() === expected.type);

	const input: CloudflareRecordInput = {
		type: expected.type,
		name: expected.name,
		content: expected.content,
		proxied: false,
		...(expected.priority != null ? { priority: expected.priority } : {})
	};

	// For MX, the identity is (type, name, priority); for everything else it is (type, name).
	const matches =
		expected.priority != null
			? sameType.filter((record) => record.priority === expected.priority)
			: sameType;

	const exact = matches.find(
		(record) => normalizeName(record.content) === normalizeName(expected.content)
	);
	if (exact) return 'unchanged';

	if (matches.length === 0) {
		await createCloudflareDnsRecord(zoneId, input);
		return 'created';
	}

	if (matches.length === 1) {
		await updateCloudflareDnsRecord(zoneId, matches[0].id, input);
		return 'updated';
	}

	throw new EmailDomainActivationError(
		`${expected.name} has several conflicting ${expected.type} records. Resolve them before activating.`,
		'ambiguous_records',
		false
	);
}

// ---------------------------------------------------------------------------------------------------
// Brevo domain reconciliation
// ---------------------------------------------------------------------------------------------------

/** Reuses an existing Brevo domain or creates it, then returns its configuration and opaque provider id. */
async function reconcileBrevoDomain(domainName: string): Promise<{
	providerDomainId: string;
	verified: boolean;
	authenticated: boolean;
	records: BrevoDnsRecord[];
}> {
	let verified: boolean;
	let authenticated: boolean;
	let records: BrevoDnsRecord[];
	try {
		const configuration = await getBrevoDomain(domainName);
		verified = configuration.verified;
		authenticated = configuration.authenticated;
		records = configuration.dns_records;
	} catch (error) {
		if (!(error instanceof BrevoManagementError) || error.status !== 404) throw error;
		await createBrevoDomain(domainName);
		const configuration = await getBrevoDomain(domainName);
		verified = configuration.verified;
		authenticated = configuration.authenticated;
		records = configuration.dns_records;
	}

	const providerDomainId = (await listBrevoDomains()).find(
		(candidate) => candidate.domain_name.toLowerCase() === domainName
	)?.id;
	if (providerDomainId == null) {
		throw new BrevoManagementError(
			'Brevo returned the domain configuration without a matching domain identity.',
			null,
			'brevo_missing_domain_id'
		);
	}

	return { providerDomainId: String(providerDomainId), verified, authenticated, records };
}

function classifyStatus(records: BrevoDnsRecord[], pattern: RegExp): DnsStatus {
	const matching = records.filter((record) => pattern.test(`${record.host_name} ${record.value}`));
	if (matching.length === 0) return 'unchecked';
	return matching.every((record) => record.status) ? 'passing' : 'pending';
}

// ---------------------------------------------------------------------------------------------------
// Row upserts. Each writes a constraint-valid row (see
// communication_email_domains_purpose_health_check / _verified_state_check).
// ---------------------------------------------------------------------------------------------------

async function findExistingDomainId(
	client: OwnerClient,
	organizationId: string,
	domainName: string,
	purpose: 'sending' | 'receiving'
): Promise<string | null> {
	const { data, error } = await client
		.from('communication_email_domains')
		.select('id, organization_id, purpose, lifecycle_state')
		.eq('domain_name', domainName)
		.neq('lifecycle_state', 'removed')
		.maybeSingle();
	if (error) throw error;
	if (!data) return null;
	if (data.organization_id !== organizationId || data.purpose !== purpose) {
		throw new EmailDomainActivationError(
			`${domainName} is already claimed by another organization or purpose.`,
			'domain_already_claimed',
			false
		);
	}
	return data.id;
}

// ---------------------------------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------------------------------

export async function activateEmailDomain(input: {
	client: OwnerClient;
	organizationId: string;
	rootDomain: string;
	webhookUrl: string;
}): Promise<ActivationResult> {
	const { client, organizationId, rootDomain, webhookUrl } = input;
	const { sending, receiving } = deriveDomains(rootDomain);
	const root = rootDomain.trim().toLowerCase();

	// The managed zone that CONTAINS the root, by longest suffix. Its apex name is needed to fully-qualify the
	// host names Brevo returns (which it shortens relative to the zone apex).
	const { id: zoneId, name: zoneName } = await resolveCloudflareZone(root);

	const sendingSummary = await reconcileSendingDomain(
		client,
		organizationId,
		zoneId,
		zoneName,
		root,
		sending
	);
	const receivingSummary = await reconcileReceivingDomain(
		client,
		organizationId,
		zoneId,
		zoneName,
		root,
		receiving,
		webhookUrl
	);

	return {
		root_domain: root,
		zone_id: zoneId,
		sending: sendingSummary,
		receiving: receivingSummary
	};
}

async function reconcileSendingDomain(
	client: OwnerClient,
	organizationId: string,
	zoneId: string,
	zoneName: string,
	root: string,
	sending: string
): Promise<ActivationDomainSummary> {
	const existingId = await findExistingDomainId(client, organizationId, sending, 'sending');

	const brevo = await reconcileBrevoDomain(sending);
	const expected = brevo.records.map((record) => brevoRecordToExpected(record, sending, zoneName));
	assertUnderSubdomain(expected, sending);

	// Occupancy: the sending subdomain apex must not already serve another service.
	assertSubdomainNotOccupied(sending, await listCloudflareDnsRecords(zoneId, sending));

	let recordsWritten = 0;
	for (const record of expected) {
		const outcome = await reconcileRecord(zoneId, record);
		if (outcome !== 'unchanged') recordsWritten += 1;
	}

	// Ask Brevo to authenticate once the records are in place; a 400 means it is not yet resolvable, which
	// is a pending (not failed) state the owner rechecks later.
	let authenticated = brevo.authenticated;
	try {
		await authenticateBrevoDomain(sending);
	} catch (error) {
		if (!(error instanceof BrevoManagementError) || error.status !== 400) throw error;
	}
	const configuration = await getBrevoDomain(sending);
	authenticated = configuration.authenticated;
	const verified = configuration.verified;
	const finalRecords = configuration.dns_records;

	const ownershipStatus = classifyStatus(finalRecords, /brevo-code|sendinblue-code/i);
	const dkimStatus = classifyStatus(finalRecords, /dkim/i);
	const ready =
		verified && authenticated && ownershipStatus === 'passing' && dkimStatus === 'passing';
	const now = new Date().toISOString();

	const row = {
		organization_id: organizationId,
		purpose: 'sending' as const,
		domain_name: sending,
		dns_zone: root,
		provider_domain_id: brevo.providerDomainId,
		provider_verified: verified,
		provider_authenticated: authenticated,
		ownership_status: ownershipStatus,
		dkim_status: dkimStatus,
		// inbound_mx_status stays 'unchecked' on a sending row (purpose_health_check).
		inbound_mx_status: 'unchecked' as const,
		dns_records:
			finalRecords as unknown as Database['public']['Tables']['communication_email_domains']['Insert']['dns_records'],
		lifecycle_state: ready ? 'verified' : 'pending_dns',
		last_checked_at: now,
		verified_at: ready ? now : null,
		updated_at: now
	};

	const domainId = await upsertDomainRow(client, existingId, row);
	return {
		domain_id: domainId,
		domain_name: sending,
		purpose: 'sending',
		lifecycle_state: row.lifecycle_state,
		provider_verified: verified,
		provider_authenticated: authenticated,
		ownership_status: ownershipStatus,
		dkim_status: dkimStatus,
		inbound_mx_status: 'unchecked',
		records_written: recordsWritten
	};
}

async function reconcileReceivingDomain(
	client: OwnerClient,
	organizationId: string,
	zoneId: string,
	zoneName: string,
	root: string,
	receiving: string,
	webhookUrl: string
): Promise<ActivationDomainSummary & { provider_inbound_webhook_id: string | null }> {
	const existingId = await findExistingDomainId(client, organizationId, receiving, 'receiving');

	const brevo = await reconcileBrevoDomain(receiving);
	const authExpected = brevo.records.map((record) =>
		brevoRecordToExpected(record, receiving, zoneName)
	);
	assertUnderSubdomain(authExpected, receiving);

	// Occupancy: an MX target that is not one of Brevo's inbound servers means the name already receives
	// mail elsewhere. Brevo's own inbound MX are allowed so a re-run is safe.
	assertSubdomainNotOccupied(receiving, await listCloudflareDnsRecords(zoneId, receiving));

	// Brevo's authentication records first, then the two documented inbound MX records.
	const mxExpected: ExpectedRecord[] = BREVO_INBOUND_MX.map((mx) => ({
		type: 'MX',
		name: receiving,
		content: mx.target,
		priority: mx.priority
	}));

	let recordsWritten = 0;
	for (const record of [...authExpected, ...mxExpected]) {
		const outcome = await reconcileRecord(zoneId, record);
		if (outcome !== 'unchanged') recordsWritten += 1;
	}

	// Brevo does not flip a receiving domain to verified on its own once the records are in place; ask it to
	// validate them -- the same nudge the sending path uses. Without this, a receiving domain stays unverified
	// even when every record resolves, and the inbound webhook can never attach. A 400 means the records are
	// not yet resolvable to Brevo, a pending (not failed) state the owner rechecks later. This runs before the
	// webhook reconcile so a domain that verifies here gets its webhook on the same pass. The UCRM row still
	// records this domain as non-sending (provider_authenticated=false) regardless of Brevo's own flag.
	try {
		await authenticateBrevoDomain(receiving);
	} catch (error) {
		if (!(error instanceof BrevoManagementError) || error.status !== 400) throw error;
	}

	// Reuse an existing domain-scoped inbound webhook or create one; store its opaque id for cleanup. Null
	// while Brevo has not yet activated the domain -- the owner's Recheck creates it once the domain verifies.
	const providerInboundWebhookId = await reconcileInboundWebhook(receiving, webhookUrl);

	const configuration = await getBrevoDomain(receiving);
	const verified = configuration.verified;
	const ownershipStatus = classifyStatus(configuration.dns_records, /brevo-code|sendinblue-code/i);
	// The authoritative zone now serves both inbound MX records, so the receiving path is in place. The
	// owner's Recheck confirms external propagation before this row is trusted for real replies.
	const inboundMxStatus: DnsStatus = 'passing';
	// Not ready until the webhook exists: a verified domain with no inbound webhook cannot receive replies.
	const ready =
		verified &&
		ownershipStatus === 'passing' &&
		inboundMxStatus === 'passing' &&
		providerInboundWebhookId !== null;
	const now = new Date().toISOString();

	const row = {
		organization_id: organizationId,
		purpose: 'receiving' as const,
		domain_name: receiving,
		dns_zone: root,
		provider_domain_id: brevo.providerDomainId,
		provider_inbound_webhook_id: providerInboundWebhookId,
		provider_verified: verified,
		// A receiving row keeps provider_authenticated=false and dkim/dmarc/spf='unchecked'
		// (purpose_health_check); its readiness is ownership + inbound MX only.
		provider_authenticated: false,
		ownership_status: ownershipStatus,
		dkim_status: 'unchecked' as const,
		dmarc_status: 'unchecked' as const,
		spf_status: 'unchecked' as const,
		inbound_mx_status: inboundMxStatus,
		dns_records:
			configuration.dns_records as unknown as Database['public']['Tables']['communication_email_domains']['Insert']['dns_records'],
		lifecycle_state: ready ? 'verified' : 'pending_dns',
		last_checked_at: now,
		verified_at: ready ? now : null,
		updated_at: now
	};

	const domainId = await upsertDomainRow(client, existingId, row);
	return {
		domain_id: domainId,
		domain_name: receiving,
		purpose: 'receiving',
		lifecycle_state: row.lifecycle_state,
		provider_verified: verified,
		provider_authenticated: false,
		ownership_status: ownershipStatus,
		dkim_status: 'unchecked',
		inbound_mx_status: inboundMxStatus,
		records_written: recordsWritten,
		provider_inbound_webhook_id: providerInboundWebhookId
	};
}

/**
 * True only for Brevo's specific refusal to attach an inbound webhook because the receiving domain is not yet
 * active (DNS written but not verified by Brevo): `400 invalid_parameter` with a "not found or is inactive"
 * message. This is a transient, expected state during DNS propagation, distinct from any other 400 -- which
 * stays a real failure.
 */
function isBrevoDomainNotActive(error: unknown): boolean {
	return (
		error instanceof BrevoManagementError &&
		error.status === 400 &&
		error.providerCode === 'invalid_parameter' &&
		/inactive|not found/i.test(error.providerMessage ?? '')
	);
}

/**
 * Reuses the single inbound webhook already pointing at the secured shared route for this receiving domain,
 * or creates one. Exactly one domain-scoped webhook is the desired state, so a pre-existing match is reused
 * rather than duplicated. Returns null when Brevo has not yet activated the domain: the webhook cannot exist
 * until Brevo verifies the DNS, so the owner's Recheck creates it on a later pass. Any other error is real.
 */
async function reconcileInboundWebhook(
	receiving: string,
	webhookUrl: string
): Promise<string | null> {
	const existing = (await listBrevoInboundWebhooks()).find(
		(webhook) =>
			webhook.domain?.toLowerCase() === receiving &&
			normalizeName(webhook.url) === normalizeName(webhookUrl)
	);
	if (existing) return String(existing.id);

	try {
		const created = await createBrevoInboundWebhook({
			url: webhookUrl,
			domain: receiving,
			description: `UCRM inbound parse for ${receiving}`
		});
		return String(created.id);
	} catch (error) {
		if (isBrevoDomainNotActive(error)) return null;
		throw error;
	}
}

/** Inserts a new domain row or updates the existing one, returning its id. Never inside a transaction. */
async function upsertDomainRow(
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
