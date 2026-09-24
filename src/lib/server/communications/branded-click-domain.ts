import { Resolver } from 'node:dns/promises';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	CloudflareDnsError,
	deleteCloudflareDnsRecord,
	listCloudflareDnsRecords,
	resolveCloudflareZone
} from './cloudflare-dns';
import {
	createClickTenant,
	deleteClickTenant,
	getClickDomainEnv,
	getClickTenant,
	getClickTenantCertificate,
	updateClickTenant,
	type ClickDomainEnv,
	type ClickTenant
} from './cloudfront';
import {
	assertUnderSubdomain,
	EmailDomainActivationError,
	normalizeName,
	reconcileRecord
} from './dns-reconcile';
import { getSesClickTrackingDomain, putSesClickTrackingDomain } from './ses';
import { SesError } from './ses-env';

// Branded click-tracking domain reconciler (Marketing M6d). It gives an organization's campaign links the
// address click.news.<root> instead of Amazon's shared awstrack.me host, the way multi-tenant email platforms
// brand tracking links: one shared CloudFront distribution in front of SES's tracking endpoint, and one
// distribution tenant with its own managed certificate per organization
// (docs/research/ses-branded-click-tracking-domain-2026-09-24.md).
//
// The one rule that keeps sends safe: the SES configuration set points at the branded domain ONLY after an
// HTTPS request to that domain has been answered by SES's tracking endpoint. In every other state links keep
// Amazon's default host, so a half-finished setup can never produce a broken link in a customer's inbox.
//
// Like the SES reconciler, every step is idempotent and a Check simply runs another pass. A step failure is
// recorded on the row as a plain-language reason instead of being thrown, so a click-link problem never fails
// the Marketing sending activation it runs inside.

export type ClickDomainStatus =
	'not_set_up' | 'waiting_certificate' | 'working' | 'turned_off' | 'problem';

export type ClickDomainSummary = {
	status: ClickDomainStatus;
	domain_name: string | null;
	error: string | null;
	checked_at: string | null;
	// False when this server has no shared distribution configured, so branded links cannot be set up here.
	configured: boolean;
};

type OwnerClient = SupabaseClient<Database>;

type ClickRow = {
	id: string;
	organization_id: string;
	domain_name: string;
	dns_zone: string | null;
	lifecycle_state: string;
	click_domain_status: ClickDomainStatus;
	click_domain_name: string | null;
	click_distribution_tenant_id: string | null;
	click_domain_error: string | null;
	click_domain_checked_at: string | null;
};

type Outcome = {
	status: ClickDomainStatus;
	domainName: string | null;
	tenantId: string | null;
	error: string | null;
};

const CLICK_LABEL = 'click';
const HEALTH_CHECK_TIMEOUT_MS = 8_000;
// Public resolvers, not the server's own: the question is whether the wider internet (and so CloudFront) can
// see the new CNAME yet, and a local cache can hold on to an old "no such name" answer.
const PUBLIC_DNS_SERVERS = ['1.1.1.1', '8.8.8.8'];
const DNS_NOT_READY_NOTE =
	'Waiting for the link address to reach the internet (usually a few minutes). Press Check again shortly.';
// SES's tracking endpoint stamps this header on every response it serves; a CloudFront error page or a
// parked domain never carries it, so it proves requests really reach SES over HTTPS.
const SES_TRACKING_HEADER = 'x-amz-ses-request-protocol';

export function clickDomainFor(marketingDomain: string): string {
	return `${CLICK_LABEL}.${marketingDomain}`;
}

function tenantNameFor(organizationId: string): string {
	return `ucrm-org-${organizationId}`;
}

function configurationSetNameFor(organizationId: string): string {
	return `ucrm-marketing-${organizationId}`;
}

// ---------------------------------------------------------------------------------------------------
// Row helpers
// ---------------------------------------------------------------------------------------------------

async function readClickRow(
	client: OwnerClient,
	organizationId: string,
	domainId: string
): Promise<ClickRow> {
	const { data, error } = await client
		.from('communication_email_domains')
		.select(
			'id, organization_id, domain_name, dns_zone, purpose, lifecycle_state, click_domain_status, click_domain_name, click_distribution_tenant_id, click_domain_error, click_domain_checked_at'
		)
		.eq('organization_id', organizationId)
		.eq('id', domainId)
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
	return data as ClickRow;
}

async function writeOutcome(
	client: OwnerClient,
	row: ClickRow,
	outcome: Outcome
): Promise<ClickDomainSummary> {
	const now = new Date().toISOString();
	const { error } = await client
		.from('communication_email_domains')
		.update({
			click_domain_status: outcome.status,
			click_domain_name: outcome.domainName,
			click_distribution_tenant_id: outcome.tenantId,
			click_domain_error: outcome.error,
			click_domain_checked_at: now,
			updated_at: now
		})
		.eq('id', row.id);
	if (error) throw error;
	return {
		status: outcome.status,
		domain_name: outcome.domainName,
		error: outcome.error,
		checked_at: now,
		configured: getClickDomainEnv() !== null
	};
}

function summaryOf(row: ClickRow): ClickDomainSummary {
	return {
		status: row.click_domain_status,
		domain_name: row.click_domain_name,
		error: row.click_domain_error,
		checked_at: row.click_domain_checked_at,
		configured: getClickDomainEnv() !== null
	};
}

/** An unknown provider outcome (timeout, network, 5xx): nothing is proven broken, so nothing is torn down. */
function isAmbiguous(error: unknown): boolean {
	if (error instanceof SesError || error instanceof CloudflareDnsError) {
		return error.status === null || error.status >= 500;
	}
	return false;
}

function plainReason(error: unknown): string {
	if (error instanceof EmailDomainActivationError) return error.message;
	if (error instanceof CloudflareDnsError) return 'Cloudflare refused the link address DNS record.';
	if (error instanceof SesError) {
		return error.code.startsWith('cloudfront_')
			? 'Amazon CloudFront refused a link setup step.'
			: 'Amazon SES refused to switch links to the branded address.';
	}
	return 'The branded link address could not be set up.';
}

// ---------------------------------------------------------------------------------------------------
// Health check
// ---------------------------------------------------------------------------------------------------

/** True when public DNS already answers the click domain with the shared distribution's routing endpoint. */
async function cnameIsVisible(domain: string, target: string): Promise<boolean> {
	// Each resolver is asked on its own: one can keep a cached "no such name" for many minutes after another
	// already sees the record. If CloudFront itself still cannot see it, the create reports that and the pass
	// keeps waiting.
	const answers = await Promise.all(
		PUBLIC_DNS_SERVERS.map(async (server) => {
			const resolver = new Resolver({ timeout: 3_000, tries: 2 });
			resolver.setServers([server]);
			try {
				return await resolver.resolveCname(domain);
			} catch {
				// NXDOMAIN, no data yet, or a resolver timeout: not visible from this resolver yet.
				return [];
			}
		})
	);
	return answers.flat().some((answer) => normalizeName(answer) === normalizeName(target));
}

/** True when an HTTPS request to the click domain is answered by SES's tracking endpoint. */
async function clickDomainAnswers(domain: string): Promise<boolean> {
	try {
		const response = await fetch(`https://${domain}/favicon.ico`, {
			method: 'HEAD',
			redirect: 'manual',
			signal: AbortSignal.timeout(HEALTH_CHECK_TIMEOUT_MS)
		});
		return response.headers.get(SES_TRACKING_HEADER)?.toLowerCase() === 'https';
	} catch {
		// A certificate not yet served, a DNS name not yet resolvable, or a timeout: not answering yet.
		return false;
	}
}

// ---------------------------------------------------------------------------------------------------
// Reconciliation
// ---------------------------------------------------------------------------------------------------

/** Links go back to Amazon's default host. Only writes when the configuration set is branded today. */
async function useDefaultLinks(organizationId: string): Promise<void> {
	const configurationSetName = configurationSetNameFor(organizationId);
	if ((await getSesClickTrackingDomain(configurationSetName)) !== null) {
		await putSesClickTrackingDomain(configurationSetName, null);
	}
}

async function findTenant(row: ClickRow): Promise<ClickTenant | null> {
	return getClickTenant(row.click_distribution_tenant_id ?? tenantNameFor(row.organization_id));
}

async function bringUp(row: ClickRow, env: ClickDomainEnv, zoneId: string): Promise<Outcome> {
	const clickDomain = clickDomainFor(row.domain_name);

	// The CNAME comes first: CloudFront validates its managed certificate through it.
	const record = { type: 'CNAME', name: clickDomain, content: env.AWS_CLICK_ROUTING_ENDPOINT };
	assertUnderSubdomain([record], row.domain_name);
	await reconcileRecord(zoneId, record);

	let tenant = await findTenant(row);
	if (!tenant) {
		// CloudFront only accepts the domain once it can see the CNAME, so a brand-new setup waits for DNS to
		// spread rather than being reported as a problem.
		const dnsNotReady: Outcome = {
			status: 'waiting_certificate',
			domainName: clickDomain,
			tenantId: null,
			error: DNS_NOT_READY_NOTE
		};
		if (!(await cnameIsVisible(clickDomain, env.AWS_CLICK_ROUTING_ENDPOINT))) return dnsNotReady;
		const created = await createClickTenant({
			env,
			name: tenantNameFor(row.organization_id),
			domain: clickDomain
		});
		if (created === 'dns_not_ready') return dnsNotReady;
		tenant = created;
	}

	if (
		tenant.distributionId !== env.AWS_CLICK_DISTRIBUTION_ID ||
		!tenant.domains.some((domain) => domain.domain === clickDomain)
	) {
		throw new EmailDomainActivationError(
			`This business's link service is set up for a different address than ${clickDomain}. Remove branded links, then turn them on again.`,
			'click_tenant_mismatch',
			false
		);
	}

	if (!tenant.enabled) tenant = await updateClickTenant(tenant, { enabled: true });

	const tenantId = tenant.id;
	const waiting = (error: string | null): Outcome => ({
		status: 'waiting_certificate',
		domainName: clickDomain,
		tenantId,
		error
	});

	// CloudFront issues the managed certificate on its own but does not attach it; attaching it is what makes
	// the domain go live (verified in the live test).
	if (!tenant.certificateArn) {
		const certificate = await getClickTenantCertificate(tenant.id);
		const status = certificate?.status ?? 'pending-validation';
		if (status === 'pending-validation') return waiting(null);
		if (status !== 'issued' || !certificate?.arn) {
			throw new EmailDomainActivationError(
				`Amazon could not issue the security certificate for ${clickDomain} (${status.replaceAll('-', ' ')}). Remove branded links, then turn them on again.`,
				'click_certificate_failed',
				false
			);
		}
		tenant = await updateClickTenant(tenant, { certificateArn: certificate.arn });
	}

	if (!(await clickDomainAnswers(clickDomain))) {
		const settling = !tenant.deployed || tenant.domains.some((domain) => !domain.active);
		if (settling) return waiting(null);
		throw new EmailDomainActivationError(
			`${clickDomain} is set up but is not answering over HTTPS. Links stay on Amazon's address until it does.`,
			'click_domain_not_answering',
			false
		);
	}

	await putSesClickTrackingDomain(configurationSetNameFor(row.organization_id), clickDomain);
	return { status: 'working', domainName: clickDomain, tenantId, error: null };
}

async function runPass(
	client: OwnerClient,
	row: ClickRow,
	zoneId: string
): Promise<ClickDomainSummary> {
	const env = getClickDomainEnv();
	if (!env) return summaryOf(row);

	try {
		const outcome = await bringUp(row, env, zoneId);
		if (outcome.status !== 'working') await useDefaultLinks(row.organization_id);
		return await writeOutcome(client, row, outcome);
	} catch (error) {
		if (isAmbiguous(error)) {
			// Keep the last known state: a working domain stays working through a brief provider outage.
			console.error('Branded click domain check did not get an answer from a provider.', error);
			return writeOutcome(client, row, {
				status: row.click_domain_status,
				domainName: row.click_domain_name,
				tenantId: row.click_distribution_tenant_id,
				error: 'Amazon or Cloudflare did not answer the link check. Press Check again.'
			});
		}
		console.error('Branded click domain step failed.', error);
		try {
			await useDefaultLinks(row.organization_id);
		} catch (resetError) {
			console.error('Could not return links to the default address.', resetError);
		}
		return writeOutcome(client, row, {
			status: 'problem',
			domainName: row.click_domain_name ?? clickDomainFor(row.domain_name),
			tenantId: row.click_distribution_tenant_id,
			error: plainReason(error)
		});
	}
}

/**
 * The click-link step of Activate and Check. Runs only once the Marketing sending identity is verified (SES
 * will not brand links for an unverified domain) and never when the owner turned branded links off.
 */
export async function reconcileClickDomain(input: {
	client: OwnerClient;
	organizationId: string;
	domainId: string;
	zoneId: string;
}): Promise<ClickDomainSummary> {
	const row = await readClickRow(input.client, input.organizationId, input.domainId);
	if (row.lifecycle_state !== 'verified' || row.click_domain_status === 'turned_off') {
		return summaryOf(row);
	}
	return runPass(input.client, row, input.zoneId);
}

// ---------------------------------------------------------------------------------------------------
// Owner controls
// ---------------------------------------------------------------------------------------------------

export type ClickDomainAction = 'turn_on' | 'turn_off' | 'remove';

export async function changeClickDomain(input: {
	client: OwnerClient;
	organizationId: string;
	domainId: string;
	action: ClickDomainAction;
}): Promise<ClickDomainSummary> {
	const row = await readClickRow(input.client, input.organizationId, input.domainId);

	if (input.action === 'turn_on') {
		if (!getClickDomainEnv()) {
			throw new EmailDomainActivationError(
				'Branded links are not configured on this server.',
				'click_domain_not_configured',
				false
			);
		}
		if (row.lifecycle_state !== 'verified') {
			throw new EmailDomainActivationError(
				'The Marketing domain must be verified before branded links can be turned on.',
				'marketing_domain_not_verified',
				false
			);
		}
		const { id: zoneId } = await resolveCloudflareZone(requireRoot(row));
		return runPass(input.client, row, zoneId);
	}

	// Both turning off and removing return links to Amazon's address first, so no send is ever left pointing
	// at a domain that is going away.
	await useDefaultLinks(row.organization_id);

	if (input.action === 'turn_off') {
		return writeOutcome(input.client, row, {
			status: 'turned_off',
			domainName: row.click_domain_name,
			tenantId: row.click_distribution_tenant_id,
			error: null
		});
	}

	return removeClickDomain(input.client, row);
}

function requireRoot(row: ClickRow): string {
	if (!row.dns_zone) {
		throw new EmailDomainActivationError(
			'This marketing domain has no recorded root domain. Run Activate again.',
			'marketing_domain_missing_root',
			false
		);
	}
	return row.dns_zone;
}

/**
 * Disables and deletes the tenant, then deletes the CNAME. CloudFront only deletes a tenant once its disable
 * has deployed (under a minute in the live test), so the first press may report that removal is finishing;
 * pressing Remove again completes it.
 */
async function removeClickDomain(client: OwnerClient, row: ClickRow): Promise<ClickDomainSummary> {
	let tenant = await findTenant(row);
	if (tenant) {
		if (tenant.enabled) tenant = await updateClickTenant(tenant, { enabled: false });
		if ((await deleteClickTenant(tenant)) === 'not_ready') {
			return writeOutcome(client, row, {
				status: 'turned_off',
				domainName: row.click_domain_name,
				tenantId: tenant.id,
				error: 'Removal is finishing at Amazon. Press Remove again in a minute.'
			});
		}
	}

	const clickDomain = row.click_domain_name ?? clickDomainFor(row.domain_name);
	const { id: zoneId } = await resolveCloudflareZone(requireRoot(row));
	for (const record of await listCloudflareDnsRecords(zoneId, clickDomain)) {
		if (
			record.type.trim().toUpperCase() === 'CNAME' &&
			normalizeName(record.name) === clickDomain &&
			normalizeName(record.content).endsWith('.cloudfront.net')
		) {
			await deleteCloudflareDnsRecord(zoneId, record.id);
		}
	}

	return writeOutcome(client, row, {
		status: 'turned_off',
		domainName: null,
		tenantId: null,
		error: null
	});
}
