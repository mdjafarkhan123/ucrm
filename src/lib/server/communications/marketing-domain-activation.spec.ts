import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	activateMarketingDomain,
	recheckMarketingDomain,
	teardownMarketingDomain
} from './marketing-domain-activation';
import { EmailDomainActivationError } from './dns-reconcile';

vi.mock('./ses', async () => {
	const actual = await vi.importActual<typeof import('./ses')>('./ses');
	return {
		...actual,
		getSesIdentity: vi.fn(),
		createSesIdentity: vi.fn(),
		putSesIdentityMailFrom: vi.fn(),
		getSesTenant: vi.fn(),
		createSesTenant: vi.fn(),
		configurationSetExists: vi.fn(),
		createSesConfigurationSet: vi.fn(),
		ensureSesEventDestination: vi.fn(),
		associateSesTenantResource: vi.fn(),
		disassociateSesTenantResource: vi.fn(),
		sesIdentityArn: vi.fn(),
		sesConfigurationSetArn: vi.fn(),
		sesMailFromMxTarget: vi.fn(),
		sesInboundMxTarget: vi.fn(),
		reconcileSesReceiptRule: vi.fn(),
		deleteSesIdentity: vi.fn()
	};
});

vi.mock('./cloudflare-dns', async () => {
	const actual = await vi.importActual<typeof import('./cloudflare-dns')>('./cloudflare-dns');
	return {
		...actual,
		resolveCloudflareZone: vi.fn(),
		listCloudflareDnsRecords: vi.fn(),
		createCloudflareDnsRecord: vi.fn(),
		updateCloudflareDnsRecord: vi.fn(),
		deleteCloudflareDnsRecord: vi.fn()
	};
});

// The branded click-link step (M6d) has its own spec; here it is a no-op that reports "not set up".
vi.mock('./branded-click-domain', () => ({
	reconcileClickDomain: vi.fn(async () => ({
		status: 'not_set_up',
		domain_name: null,
		error: null,
		checked_at: null,
		configured: false
	}))
}));

import * as ses from './ses';
import * as cloudflare from './cloudflare-dns';

const ORG = '11111111-1111-1111-1111-111111111111';
const ROOT = 'contractor.com';
const MARKETING = 'news.contractor.com';
const MAIL_FROM = 'bounce.news.contractor.com';
const MX_TARGET = 'feedback-smtp.us-east-1.amazonses.com';
const INBOUND_MX = 'inbound-smtp.us-east-1.amazonaws.com';
const IDENTITY_ARN = `arn:aws:ses:us-east-1:881776924275:identity/${MARKETING}`;
const CONFIG_SET_ARN = `arn:aws:ses:us-east-1:881776924275:configuration-set/ucrm-marketing-${ORG}`;

type DomainRow = {
	id: string;
	organization_id: string;
	purpose: string;
	lifecycle_state: string;
	domain_name?: string;
	dns_zone?: string | null;
	verified_at?: string | null;
};

/**
 * Minimal fake of the owner Supabase client covering the two tables this reconciler touches. Answers the
 * existing-domain lookup (by name or by id) from a preset map, and records every write so a test can assert
 * exactly what the reconciler decided to store.
 */
function makeClient(existing: DomainRow[] = []) {
	const inserted: Record<string, unknown>[] = [];
	const updated: { id: string; row: Record<string, unknown> }[] = [];
	const tenantUpserts: Record<string, unknown>[] = [];
	let idSeq = 0;

	const from = (table: string) => {
		let op: 'select' | 'insert' | 'update' = 'select';
		let payload: Record<string, unknown> = {};
		const filters: Record<string, unknown> = {};
		const builder: Record<string, unknown> = {
			select: () => builder,
			insert: (row: Record<string, unknown>) => {
				op = 'insert';
				payload = row;
				return builder;
			},
			update: (row: Record<string, unknown>) => {
				op = 'update';
				payload = row;
				return builder;
			},
			upsert: (row: Record<string, unknown>) => {
				tenantUpserts.push(row);
				return Promise.resolve({ error: null });
			},
			neq: () => builder,
			eq: (col: string, val: unknown) => {
				filters[col] = val;
				if (op === 'update') {
					updated.push({ id: String(val), row: payload });
					return Promise.resolve({ error: null });
				}
				return builder;
			},
			maybeSingle: () => {
				const match = existing.find((row) =>
					filters.domain_name != null
						? row.domain_name === filters.domain_name
						: row.id === filters.id
				);
				return Promise.resolve({ data: match ?? null, error: null });
			},
			single: () => {
				idSeq += 1;
				const id = `domain-${idSeq}`;
				inserted.push({ id, ...payload });
				return Promise.resolve({ data: { id }, error: null });
			}
		};
		void table;
		return builder;
	};

	return {
		client: { from } as unknown as SupabaseClient<Database>,
		inserted,
		updated,
		tenantUpserts
	};
}

function identity(overrides: Partial<ses.SesIdentity> = {}): ses.SesIdentity {
	return {
		verifiedForSending: true,
		dkimStatus: 'SUCCESS',
		dkimSigningEnabled: true,
		dkimTokens: ['tok1', 'tok2', 'tok3'],
		mailFromDomain: MAIL_FROM,
		mailFromStatus: 'SUCCESS',
		...overrides
	};
}

beforeEach(() => {
	vi.clearAllMocks();
	vi.mocked(cloudflare.resolveCloudflareZone).mockResolvedValue({ id: 'zone-1', name: ROOT });
	vi.mocked(cloudflare.listCloudflareDnsRecords).mockResolvedValue([]);
	vi.mocked(cloudflare.createCloudflareDnsRecord).mockImplementation(async (_zone, input) => ({
		id: 'cf-new',
		type: input.type,
		name: input.name,
		content: input.content,
		ttl: 1,
		priority: input.priority ?? null,
		proxied: false
	}));
	vi.mocked(ses.getSesTenant).mockResolvedValue({ tenantArn: `arn:aws:ses:tenant/${ORG}` });
	vi.mocked(ses.configurationSetExists).mockResolvedValue(true);
	vi.mocked(ses.ensureSesEventDestination).mockResolvedValue(true);
	vi.mocked(ses.getSesIdentity).mockResolvedValue(identity());
	vi.mocked(ses.sesIdentityArn).mockReturnValue(IDENTITY_ARN);
	vi.mocked(ses.sesConfigurationSetArn).mockReturnValue(CONFIG_SET_ARN);
	vi.mocked(ses.sesMailFromMxTarget).mockReturnValue(MX_TARGET);
	vi.mocked(ses.sesInboundMxTarget).mockReturnValue(INBOUND_MX);
});

describe('activateMarketingDomain', () => {
	it('writes the DKIM, MX, SPF, and From-reply MX records the SES identity needs, and nothing else', async () => {
		const { client } = makeClient();

		await activateMarketingDomain({ client, organizationId: ORG, rootDomain: ROOT });

		const written = vi
			.mocked(cloudflare.createCloudflareDnsRecord)
			.mock.calls.map(([, input]) => input);
		expect(written).toEqual([
			{
				type: 'CNAME',
				name: `tok1._domainkey.${MARKETING}`,
				content: 'tok1.dkim.amazonses.com',
				proxied: false
			},
			{
				type: 'CNAME',
				name: `tok2._domainkey.${MARKETING}`,
				content: 'tok2.dkim.amazonses.com',
				proxied: false
			},
			{
				type: 'CNAME',
				name: `tok3._domainkey.${MARKETING}`,
				content: 'tok3.dkim.amazonses.com',
				proxied: false
			},
			{ type: 'MX', name: MAIL_FROM, content: MX_TARGET, proxied: false, priority: 10 },
			{
				type: 'TXT',
				name: MAIL_FROM,
				content: 'v=spf1 include:amazonses.com ~all',
				proxied: false
			},
			// Replies to the From address: news.<root> receives once SES has verified it.
			{ type: 'MX', name: MARKETING, content: INBOUND_MX, proxied: false, priority: 10 }
		]);
		expect(ses.reconcileSesReceiptRule).toHaveBeenCalled();
	});

	it('does not route From replies to SES before the identity is verified', async () => {
		vi.mocked(ses.getSesIdentity).mockResolvedValue(
			identity({ dkimStatus: 'PENDING', verifiedForSending: false })
		);
		const { client } = makeClient();

		await activateMarketingDomain({ client, organizationId: ORG, rootDomain: ROOT });

		const written = vi
			.mocked(cloudflare.createCloudflareDnsRecord)
			.mock.calls.map(([, input]) => input);
		expect(written.some((record) => record.name === MARKETING)).toBe(false);
		expect(ses.reconcileSesReceiptRule).not.toHaveBeenCalled();
	});

	it('refuses a marketing subdomain that already routes mail somewhere else', async () => {
		vi.mocked(cloudflare.listCloudflareDnsRecords).mockImplementation(async (_zone, name) =>
			name === MARKETING
				? [
						{
							id: 'mx1',
							type: 'MX',
							name: MARKETING,
							content: 'mx.mailbox-host.com',
							ttl: 1,
							priority: 10,
							proxied: false
						}
					]
				: []
		);
		const { client } = makeClient();

		await expect(
			activateMarketingDomain({ client, organizationId: ORG, rootDomain: ROOT })
		).rejects.toMatchObject({ code: 'subdomain_occupied' });
		expect(cloudflare.createCloudflareDnsRecord).not.toHaveBeenCalled();
	});

	it('never writes outside the marketing subdomain', async () => {
		const { client } = makeClient();

		await activateMarketingDomain({ client, organizationId: ORG, rootDomain: ROOT });

		for (const [, input] of vi.mocked(cloudflare.createCloudflareDnsRecord).mock.calls) {
			expect(input.name.endsWith(`.${MARKETING}`) || input.name === MARKETING).toBe(true);
		}
		// The operational names and the root itself are never even read, let alone written.
		const inspected = vi
			.mocked(cloudflare.listCloudflareDnsRecords)
			.mock.calls.map(([, name]) => name);
		for (const name of inspected) {
			expect(name.endsWith(`.${MARKETING}`) || name === MARKETING).toBe(true);
		}
		expect(inspected).toContain(MARKETING);
		expect(inspected).toContain(MAIL_FROM);
	});

	it('stores a marketing_sending row on the ses provider once DKIM and SPF both pass', async () => {
		const { client, inserted } = makeClient();

		const result = await activateMarketingDomain({ client, organizationId: ORG, rootDomain: ROOT });

		expect(result.marketing.lifecycle_state).toBe('verified');
		expect(inserted[0]).toMatchObject({
			organization_id: ORG,
			purpose: 'marketing_sending',
			provider: 'ses',
			domain_name: MARKETING,
			dns_zone: ROOT,
			provider_domain_id: IDENTITY_ARN,
			ownership_status: 'passing',
			dkim_status: 'passing',
			spf_status: 'passing',
			// A marketing row must leave the receiving-only health value alone
			// (communication_email_domains_purpose_health_check).
			inbound_mx_status: 'unchecked',
			dmarc_status: 'unchecked',
			lifecycle_state: 'verified'
		});
		expect(inserted[0].verified_at).toBeTruthy();
	});

	it('stays pending while the custom MAIL FROM has not verified, because SPF alignment is missing', async () => {
		vi.mocked(ses.getSesIdentity).mockResolvedValue(identity({ mailFromStatus: 'PENDING' }));
		const { client, inserted } = makeClient();

		const result = await activateMarketingDomain({ client, organizationId: ORG, rootDomain: ROOT });

		expect(result.marketing.spf_status).toBe('pending');
		expect(result.marketing.lifecycle_state).toBe('pending_dns');
		expect(inserted[0].verified_at).toBeNull();
	});

	it('treats a temporary SES failure as pending rather than failing', async () => {
		vi.mocked(ses.getSesIdentity).mockResolvedValue(
			identity({ dkimStatus: 'TEMPORARY_FAILURE', mailFromStatus: 'TEMPORARY_FAILURE' })
		);
		const { client } = makeClient();

		const result = await activateMarketingDomain({ client, organizationId: ORG, rootDomain: ROOT });

		expect(result.marketing.dkim_status).toBe('pending');
		expect(result.marketing.spf_status).toBe('pending');
	});

	it('creates the identity and reads its DKIM tokens back when SES does not have it yet', async () => {
		vi.mocked(ses.getSesIdentity)
			.mockResolvedValueOnce(null)
			.mockResolvedValue(identity({ dkimTokens: ['newtok'] }));
		const { client } = makeClient();

		await activateMarketingDomain({ client, organizationId: ORG, rootDomain: ROOT });

		expect(ses.createSesIdentity).toHaveBeenCalledWith(MARKETING);
		const written = vi
			.mocked(cloudflare.createCloudflareDnsRecord)
			.mock.calls.map(([, input]) => input.name);
		expect(written).toContain(`newtok._domainkey.${MARKETING}`);
	});

	it('points the identity at the custom MAIL FROM only while it is not already set', async () => {
		const { client } = makeClient();
		await activateMarketingDomain({ client, organizationId: ORG, rootDomain: ROOT });
		expect(ses.putSesIdentityMailFrom).not.toHaveBeenCalled();

		vi.clearAllMocks();
		vi.mocked(cloudflare.resolveCloudflareZone).mockResolvedValue({ id: 'zone-1', name: ROOT });
		vi.mocked(cloudflare.listCloudflareDnsRecords).mockResolvedValue([]);
		vi.mocked(ses.getSesTenant).mockResolvedValue({ tenantArn: 'arn:tenant' });
		vi.mocked(ses.configurationSetExists).mockResolvedValue(true);
		vi.mocked(ses.ensureSesEventDestination).mockResolvedValue(true);
		vi.mocked(ses.sesIdentityArn).mockReturnValue(IDENTITY_ARN);
		vi.mocked(ses.sesConfigurationSetArn).mockReturnValue(CONFIG_SET_ARN);
		vi.mocked(ses.sesMailFromMxTarget).mockReturnValue(MX_TARGET);
		vi.mocked(ses.getSesIdentity).mockResolvedValue(identity({ mailFromDomain: null }));

		const second = makeClient();
		await activateMarketingDomain({
			client: second.client,
			organizationId: ORG,
			rootDomain: ROOT
		});
		expect(ses.putSesIdentityMailFrom).toHaveBeenCalledWith(MARKETING, MAIL_FROM);
	});

	it('authorizes the tenant for both the identity and the configuration set on every pass', async () => {
		const { client } = makeClient();

		await activateMarketingDomain({ client, organizationId: ORG, rootDomain: ROOT });

		expect(ses.associateSesTenantResource).toHaveBeenCalledWith(`ucrm-org-${ORG}`, IDENTITY_ARN);
		expect(ses.associateSesTenantResource).toHaveBeenCalledWith(`ucrm-org-${ORG}`, CONFIG_SET_ARN);
	});

	it('records the organization tenant and configuration set', async () => {
		const { client, tenantUpserts } = makeClient();

		await activateMarketingDomain({ client, organizationId: ORG, rootDomain: ROOT });

		expect(tenantUpserts[0]).toMatchObject({
			organization_id: ORG,
			tenant_name: `ucrm-org-${ORG}`,
			configuration_set_name: `ucrm-marketing-${ORG}`,
			event_destination_ready: true
		});
	});

	it('refuses a bounce name that already routes mail somewhere else', async () => {
		vi.mocked(cloudflare.listCloudflareDnsRecords).mockImplementation(async (_zone, name) =>
			name === MAIL_FROM
				? [
						{
							id: 'cf-1',
							type: 'MX',
							name,
							content: 'mx.othermail.com',
							ttl: 1,
							priority: 10,
							proxied: false
						}
					]
				: []
		);
		const { client } = makeClient();

		await expect(
			activateMarketingDomain({ client, organizationId: ORG, rootDomain: ROOT })
		).rejects.toMatchObject({ code: 'subdomain_occupied', retryable: false });
		expect(cloudflare.createCloudflareDnsRecord).not.toHaveBeenCalled();
	});

	it('refuses a marketing domain another organization already claims', async () => {
		const { client } = makeClient([
			{
				id: 'domain-9',
				organization_id: '22222222-2222-2222-2222-222222222222',
				purpose: 'marketing_sending',
				lifecycle_state: 'verified',
				domain_name: MARKETING
			}
		]);

		await expect(
			activateMarketingDomain({ client, organizationId: ORG, rootDomain: ROOT })
		).rejects.toMatchObject({ code: 'domain_already_claimed' });
	});

	it('rejects a root domain that is not a domain name', async () => {
		const { client } = makeClient();
		await expect(
			activateMarketingDomain({ client, organizationId: ORG, rootDomain: 'not a domain' })
		).rejects.toBeInstanceOf(EmailDomainActivationError);
	});
});

describe('recheckMarketingDomain', () => {
	const existingRow: DomainRow = {
		id: 'domain-7',
		organization_id: ORG,
		purpose: 'marketing_sending',
		lifecycle_state: 'verified',
		domain_name: MARKETING,
		dns_zone: ROOT,
		verified_at: '2026-09-01T00:00:00.000Z'
	};

	it('updates the existing row instead of inserting a second one', async () => {
		const { client, inserted, updated } = makeClient([existingRow]);

		await recheckMarketingDomain({ client, organizationId: ORG, domainId: 'domain-7' });

		expect(inserted).toHaveLength(0);
		expect(updated[0].id).toBe('domain-7');
	});

	it('keeps the original verified date when a healthy domain is rechecked', async () => {
		const { client, updated } = makeClient([existingRow]);

		await recheckMarketingDomain({ client, organizationId: ORG, domainId: 'domain-7' });

		expect(updated[0].row.verified_at).toBe('2026-09-01T00:00:00.000Z');
	});

	it('marks a domain that has verified before and now fails as unhealthy, not pending', async () => {
		vi.mocked(ses.getSesIdentity).mockResolvedValue(
			identity({ dkimStatus: 'FAILED', dkimSigningEnabled: false, verifiedForSending: false })
		);
		const { client, updated } = makeClient([existingRow]);

		const result = await recheckMarketingDomain({
			client,
			organizationId: ORG,
			domainId: 'domain-7'
		});

		expect(result.marketing.lifecycle_state).toBe('unhealthy');
		expect(result.marketing.dkim_status).toBe('failing');
		expect(updated[0].row.verified_at).toBe('2026-09-01T00:00:00.000Z');
	});

	it('refuses to recheck a row that is not a marketing sending domain', async () => {
		const { client } = makeClient([{ ...existingRow, purpose: 'sending' }]);

		await expect(
			recheckMarketingDomain({ client, organizationId: ORG, domainId: 'domain-7' })
		).rejects.toMatchObject({ code: 'marketing_domain_not_found' });
	});

	it('refuses a row whose name does not match its recorded root domain', async () => {
		const { client } = makeClient([{ ...existingRow, dns_zone: 'somewhere-else.com' }]);

		await expect(
			recheckMarketingDomain({ client, organizationId: ORG, domainId: 'domain-7' })
		).rejects.toMatchObject({ code: 'marketing_domain_mismatch' });
	});
});

describe('teardownMarketingDomain', () => {
	function record(id: string, type: string, name: string, content: string) {
		return { id, type, name, content, ttl: 1, priority: null, proxied: false };
	}

	it('stops receiving first, then deletes only the records UCRM wrote and the identity', async () => {
		const order: string[] = [];
		const zone: Record<string, ReturnType<typeof record>[]> = {
			[MARKETING]: [
				record('news-mx', 'MX', MARKETING, INBOUND_MX),
				record('someone-else', 'TXT', MARKETING, 'google-site-verification=abc')
			],
			[`tok1._domainkey.${MARKETING}`]: [
				record('tok1', 'CNAME', `tok1._domainkey.${MARKETING}`, 'tok1.dkim.amazonses.com')
			],
			[MAIL_FROM]: [
				record('mf-mx', 'MX', MAIL_FROM, MX_TARGET),
				record('mf-txt', 'TXT', MAIL_FROM, '"v=spf1 include:amazonses.com ~all"')
			]
		};
		vi.mocked(cloudflare.listCloudflareDnsRecords).mockImplementation(
			async (_zone, name) => zone[name] ?? []
		);
		vi.mocked(cloudflare.deleteCloudflareDnsRecord).mockImplementation(async (_zone, id) => {
			order.push(`dns:${id}`);
		});
		vi.mocked(ses.deleteSesIdentity).mockImplementation(async (domain) => {
			order.push(`identity:${domain}`);
		});
		vi.mocked(ses.disassociateSesTenantResource).mockImplementation(async (tenant, arn) => {
			order.push(`unlink:${tenant}:${arn}`);
		});

		await teardownMarketingDomain({ organizationId: ORG, rootDomain: ROOT });

		// SES refuses to delete an identity a tenant still uses, so it is unlinked just before the delete.
		expect(order.indexOf(`unlink:ucrm-org-${ORG}:${IDENTITY_ARN}`)).toBe(
			order.indexOf(`identity:${MARKETING}`) - 1
		);

		expect(order[0]).toBe('dns:news-mx');
		expect(order).toEqual(
			expect.arrayContaining(['dns:tok1', `identity:${MARKETING}`, 'dns:mf-mx', 'dns:mf-txt'])
		);
		expect(order).not.toContain('dns:someone-else');
	});
});
