import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { EmailDomainActivationError, type ExpectedRecord } from './dns-reconcile';
import {
	configurationSetExists,
	createSesConfigurationSet,
	createSesIdentity,
	createSesTenant,
	ensureSesEventDestination,
	getSesIdentity,
	getSesTenant,
	sesMailFromMxTarget,
	type SesIdentity
} from './ses';

// The SES half of managed domain activation, shared by the Marketing reconciler and the operational (everyday
// email) reconciler. Both provision SES identities in the organization's one SES tenant; keeping the tenant,
// identity, status, and row rules here means the two streams cannot drift into different definitions of
// "verified".

export type DnsStatus = 'unchecked' | 'pending' | 'passing' | 'failing';
export type OwnerClient = SupabaseClient<Database>;
type DomainInsert = Database['public']['Tables']['communication_email_domains']['Insert'];

// SES publishes the sending domain's SPF through its own include. A MAIL FROM subdomain is a UCRM-owned name
// that serves nothing else, so a strict-ish `~all` is safe and is what AWS documents.
const MAIL_FROM_SPF_VALUE = 'v=spf1 include:amazonses.com ~all';
const MAIL_FROM_MX_PRIORITY = 10;

export const ROOT_DOMAIN_PATTERN =
	/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;

export function normalizeRootDomain(rootDomain: string): string {
	const root = rootDomain.trim().toLowerCase();
	if (!ROOT_DOMAIN_PATTERN.test(root)) {
		throw new EmailDomainActivationError(
			'The root domain is not a valid domain name.',
			'invalid_root_domain',
			false
		);
	}
	return root;
}

/**
 * The organization's SES tenant name. Global within the AWS account and derived, never stored-then-guessed, so a
 * half-finished run re-derives exactly the same name. Matches communication_ses_tenants'
 * `^[A-Za-z0-9_-]{1,64}$` check (a UUID is hex and hyphens).
 */
export function sesTenantName(organizationId: string): string {
	return `ucrm-org-${organizationId}`;
}

export function marketingConfigurationSetName(organizationId: string): string {
	return `ucrm-marketing-${organizationId}`;
}

// Operational mail gets its own configuration set so its delivery events, and later its reputation, are never
// mixed with a campaign's: an invoice must not inherit a newsletter's complaint rate.
export function operationalConfigurationSetName(organizationId: string): string {
	return `ucrm-operational-${organizationId}`;
}

/**
 * Maps an SES verification status onto the four-state health value this table already uses everywhere.
 * TEMPORARY_FAILURE is 'pending', not 'failing': SES retries these on its own for up to 72 hours, so calling
 * it a failure would make a healthy activation look broken while DNS is still settling.
 */
export function sesStatusToDns(status: string | null | undefined): DnsStatus {
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

/**
 * Brings the organization's SES tenant and its Marketing configuration set (with event destination) to their
 * desired state and records them. A tenant is per organization rather than per domain because it outlives a
 * domain replacement, and it is what keeps one contractor's reputation enforcement and suppression off
 * another's. The tenant row carries the Marketing configuration set, so whichever stream is set up first
 * creates it; an unused configuration set costs nothing.
 */
export async function reconcileSesTenant(
	client: OwnerClient,
	organizationId: string
): Promise<{ tenantName: string; tenantArn: string | null; configurationSetName: string }> {
	const tenantName = sesTenantName(organizationId);
	const configurationSetName = marketingConfigurationSetName(organizationId);

	const existingTenant = await getSesTenant(tenantName);
	const tenant = existingTenant ?? (await createSesTenant(tenantName));

	await ensureSesConfigurationSet(configurationSetName);
	// Without this the Marketing dispatcher would send successfully and never learn what happened to it.
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

export async function ensureSesConfigurationSet(configurationSetName: string): Promise<void> {
	if (!(await configurationSetExists(configurationSetName))) {
		await createSesConfigurationSet(configurationSetName);
	}
}

/** Reuses the SES domain identity or creates it with Easy DKIM, then reads back its DKIM tokens. */
export async function reconcileSesIdentity(domain: string): Promise<SesIdentity> {
	const existing = await getSesIdentity(domain);
	if (existing) return existing;

	await createSesIdentity(domain);
	const created = await getSesIdentity(domain);
	if (!created) {
		throw new EmailDomainActivationError(
			`Amazon SES accepted the identity for ${domain} but did not return it. Try the check again.`,
			'ses_identity_not_readable',
			true
		);
	}
	return created;
}

/** The three Easy DKIM CNAMEs under the identity's domain. With Easy DKIM these are also the ownership proof. */
export function sesDkimRecords(identity: SesIdentity, domain: string): ExpectedRecord[] {
	return identity.dkimTokens.map((token) => ({
		type: 'CNAME',
		name: `${token}._domainkey.${domain}`,
		content: `${token}.dkim.amazonses.com`
	}));
}

/** The MX plus SPF TXT that give a custom MAIL FROM subdomain its own bounce path and SPF alignment. */
export function sesMailFromRecords(mailFrom: string): ExpectedRecord[] {
	return [
		{ type: 'MX', name: mailFrom, content: sesMailFromMxTarget(), priority: MAIL_FROM_MX_PRIORITY },
		{ type: 'TXT', name: mailFrom, content: MAIL_FROM_SPF_VALUE }
	];
}

export function toStoredDnsRecords(records: ExpectedRecord[]): DomainInsert['dns_records'] {
	return records.map((record) => ({
		type: record.type,
		host_name: record.name,
		value: record.content,
		...(record.priority != null ? { priority: record.priority } : {})
	})) as unknown as DomainInsert['dns_records'];
}

/**
 * The live row for this domain, or null. communication_email_domains_live_claim_idx allows one live row per
 * domain_name across the whole platform, so a name already claimed by another organization or purpose is a
 * conflict a human resolves rather than something activation may take over.
 */
export async function findExistingDomainId(
	client: OwnerClient,
	organizationId: string,
	domainName: string,
	purpose: 'sending' | 'receiving' | 'marketing_sending'
): Promise<string | null> {
	const { data, error } = await client
		.from('communication_email_domains')
		.select('id, organization_id, purpose')
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

/**
 * What an existing row already recorded. A domain that has verified before turns a later failed check into
 * 'unhealthy' rather than back into 'pending_dns', and keeps its original verified_at.
 */
export async function readDomainHistory(
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

export function nextLifecycleState(
	ready: boolean,
	history: { verifiedAt: string | null; lifecycleState: string | null }
): 'pending_dns' | 'verified' | 'unhealthy' {
	if (ready) return 'verified';
	const previouslyVerified = Boolean(history.verifiedAt) || history.lifecycleState === 'unhealthy';
	return previouslyVerified ? 'unhealthy' : 'pending_dns';
}

/** Inserts a new domain row or updates the existing one, returning its id. Never inside a transaction. */
export async function upsertDomainRow(
	client: OwnerClient,
	existingId: string | null,
	row: DomainInsert
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
