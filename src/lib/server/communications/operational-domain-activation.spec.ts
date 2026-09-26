import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	activateOperationalDomain,
	recheckOperationalDomain,
	teardownOperationalDomain
} from './operational-domain-activation';
import { EmailDomainActivationError } from './dns-reconcile';

vi.mock('./ses', async () => {
	const actual = await vi.importActual<typeof import('./ses')>('./ses');
	return {
		...actual,
		getSesIdentity: vi.fn(),
		createSesIdentity: vi.fn(),
		deleteSesIdentity: vi.fn(),
		putSesIdentityMailFrom: vi.fn(),
		getSesTenant: vi.fn(),
		createSesTenant: vi.fn(),
		configurationSetExists: vi.fn(),
		createSesConfigurationSet: vi.fn(),
		ensureSesEventDestination: vi.fn(),
		associateSesTenantResource: vi.fn(),
		sesIdentityArn: vi.fn(),
		sesConfigurationSetArn: vi.fn(),
		sesMailFromMxTarget: vi.fn(),
		sesInboundMxTarget: vi.fn(),
		reconcileSesReceiptRule: vi.fn()
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

vi.mock('./operational-reply-ingestion', async () => ({
	...(await vi.importActual<typeof import('./operational-reply-ingestion')>(
		'./operational-reply-ingestion'
	)),
	reconcileReplyIngestion: vi.fn()
}));

import * as ses from './ses';
import * as cloudflare from './cloudflare-dns';
import { reconcileReplyIngestion } from './operational-reply-ingestion';

const ORG = '11111111-1111-1111-1111-111111111111';
const ROOT = 'contractor.com';
const SENDING = 'mail.contractor.com';
const RECEIVING = 'reply.contractor.com';
const MAIL_FROM = 'bounce.mail.contractor.com';
const MAIL_FROM_MX = 'feedback-smtp.us-east-1.amazonses.com';
const INBOUND_MX = 'inbound-smtp.us-east-1.amazonaws.com';
const OPERATIONAL_SET = `ucrm-operational-${ORG}`;

type DomainRow = {
	id: string;
	organization_id: string;
	purpose: string;
	lifecycle_state: string;
	provider?: string;
	domain_name?: string;
	dns_zone?: string | null;
	verified_at?: string | null;
	inbound_mx_status?: string;
};

/**
 * Minimal fake of the owner Supabase client. Answers row lookups (by name or by id) from a preset list and
 * records every write, so a test can assert exactly what the reconciler decided to store.
 */
function makeClient(existing: DomainRow[] = []) {
	const inserted: Record<string, unknown>[] = [];
	const updated: { id: string; row: Record<string, unknown> }[] = [];

	const from = () => {
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
			upsert: () => Promise.resolve({ error: null }),
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
				const id = `domain-${inserted.length + 1}`;
				inserted.push({ id, ...payload });
				return Promise.resolve({ data: { id }, error: null });
			}
		};
		return builder;
	};

	return { client: { from } as unknown as SupabaseClient<Database>, inserted, updated };
}

function identity(domain: string, overrides: Partial<ses.SesIdentity> = {}): ses.SesIdentity {
	const prefix = domain === SENDING ? 's' : 'r';
	return {
		verifiedForSending: true,
		dkimStatus: 'SUCCESS',
		dkimSigningEnabled: true,
		dkimTokens: [`${prefix}1`, `${prefix}2`, `${prefix}3`],
		mailFromDomain: domain === SENDING ? MAIL_FROM : null,
		mailFromStatus: domain === SENDING ? 'SUCCESS' : null,
		...overrides
	};
}

function writtenRecords() {
	return vi.mocked(cloudflare.createCloudflareDnsRecord).mock.calls.map(([, input]) => input);
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
	vi.mocked(ses.getSesIdentity).mockImplementation(async (domain) => identity(domain));
	vi.mocked(ses.sesIdentityArn).mockImplementation((domain) => `arn:identity/${domain}`);
	vi.mocked(ses.sesConfigurationSetArn).mockImplementation((name) => `arn:config-set/${name}`);
	vi.mocked(ses.sesMailFromMxTarget).mockReturnValue(MAIL_FROM_MX);
	vi.mocked(ses.sesInboundMxTarget).mockReturnValue(INBOUND_MX);
	vi.mocked(reconcileReplyIngestion).mockResolvedValue({
		domain_id: 'ses-receiving',
		lifecycle_state: 'pending_dns',
		inbound_mx_status: 'pending',
		records_written: 1
	});
});

describe('activateOperationalDomain', () => {
	it('writes DKIM for both identities, the MAIL FROM records, and the From-reply MX once verified', async () => {
		const { client } = makeClient();

		await activateOperationalDomain({ client, organizationId: ORG, rootDomain: ROOT });

		expect(writtenRecords()).toEqual([
			...['s1', 's2', 's3'].map((token) => ({
				type: 'CNAME',
				name: `${token}._domainkey.${SENDING}`,
				content: `${token}.dkim.amazonses.com`,
				proxied: false
			})),
			{ type: 'MX', name: MAIL_FROM, content: MAIL_FROM_MX, proxied: false, priority: 10 },
			{
				type: 'TXT',
				name: MAIL_FROM,
				content: 'v=spf1 include:amazonses.com ~all',
				proxied: false
			},
			...['r1', 'r2', 'r3'].map((token) => ({
				type: 'CNAME',
				name: `${token}._domainkey.${RECEIVING}`,
				content: `${token}.dkim.amazonses.com`,
				proxied: false
			})),
			// Replies to the From address: the shared receipt rule first, then mail.<root> receives too.
			{ type: 'MX', name: SENDING, content: INBOUND_MX, proxied: false, priority: 10 }
		]);
		expect(ses.reconcileSesReceiptRule).toHaveBeenCalled();
	});

	it('records the From-reply MX on the sending row, whose inbound status stays unchecked', async () => {
		const { client, inserted } = makeClient();

		await activateOperationalDomain({ client, organizationId: ORG, rootDomain: ROOT });

		expect(inserted[0].inbound_mx_status).toBe('unchecked');
		expect(inserted[0].dns_records).toContainEqual(
			expect.objectContaining({ type: 'MX', host_name: SENDING, value: INBOUND_MX })
		);
	});

	it('keeps an SES inbound MX already on mail.<root>, so a Recheck is safe', async () => {
		vi.mocked(cloudflare.listCloudflareDnsRecords).mockImplementation(async (_zone, name) =>
			name === SENDING
				? [
						{
							id: 'mail-mx',
							type: 'MX',
							name: SENDING,
							content: INBOUND_MX,
							ttl: 1,
							priority: 10,
							proxied: false
						}
					]
				: []
		);
		const { client } = makeClient();

		const result = await activateOperationalDomain({
			client,
			organizationId: ORG,
			rootDomain: ROOT
		});

		expect(result.sending.lifecycle_state).toBe('verified');
		expect(writtenRecords().some((record) => record.name === SENDING)).toBe(false);
	});

	it('refuses a sending subdomain that already routes mail somewhere else', async () => {
		vi.mocked(cloudflare.listCloudflareDnsRecords).mockImplementation(async (_zone, name) =>
			name === SENDING
				? [
						{
							id: 'mx1',
							type: 'MX',
							name: SENDING,
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
			activateOperationalDomain({ client, organizationId: ORG, rootDomain: ROOT })
		).rejects.toMatchObject({ code: 'subdomain_occupied' });
		expect(cloudflare.createCloudflareDnsRecord).not.toHaveBeenCalled();
	});

	it('never reads or writes the root domain', async () => {
		const { client } = makeClient();

		await activateOperationalDomain({ client, organizationId: ORG, rootDomain: ROOT });

		const inspected = vi
			.mocked(cloudflare.listCloudflareDnsRecords)
			.mock.calls.map(([, name]) => name);
		for (const name of [...inspected, ...writtenRecords().map((record) => record.name)]) {
			expect(
				name.endsWith(`.${SENDING}`) ||
					name === SENDING ||
					name.endsWith(`.${RECEIVING}`) ||
					name === RECEIVING
			).toBe(true);
		}
	});

	it('creates the operational configuration set in the organization tenant and authorizes it', async () => {
		vi.mocked(ses.configurationSetExists).mockImplementation(
			async (name) => name !== OPERATIONAL_SET
		);
		const { client } = makeClient();

		const result = await activateOperationalDomain({
			client,
			organizationId: ORG,
			rootDomain: ROOT
		});

		expect(ses.createSesConfigurationSet).toHaveBeenCalledWith(OPERATIONAL_SET);
		expect(ses.associateSesTenantResource).toHaveBeenCalledWith(
			`ucrm-org-${ORG}`,
			`arn:identity/${SENDING}`
		);
		expect(ses.associateSesTenantResource).toHaveBeenCalledWith(
			`ucrm-org-${ORG}`,
			`arn:config-set/${OPERATIONAL_SET}`
		);
		expect(result.sending.configuration_set_name).toBe(OPERATIONAL_SET);
		expect(ses.ensureSesEventDestination).toHaveBeenCalledWith(OPERATIONAL_SET);
		expect(result.sending.event_destination_ready).toBe(true);
	});

	it('stores a verified sending row on SES once the identity and DKIM pass', async () => {
		const { client, inserted } = makeClient();

		const result = await activateOperationalDomain({
			client,
			organizationId: ORG,
			rootDomain: ROOT
		});

		expect(result.sending.lifecycle_state).toBe('verified');
		expect(inserted).toHaveLength(1);
		expect(inserted[0]).toMatchObject({
			purpose: 'sending',
			provider: 'ses',
			domain_name: SENDING,
			dns_zone: ROOT,
			provider_domain_id: `arn:identity/${SENDING}`,
			ownership_status: 'passing',
			dkim_status: 'passing',
			spf_status: 'passing',
			inbound_mx_status: 'unchecked',
			lifecycle_state: 'verified'
		});
	});

	it('does not wait on MAIL FROM, because SES falls back to its own until it resolves', async () => {
		vi.mocked(ses.getSesIdentity).mockImplementation(async (domain) =>
			identity(domain, { mailFromStatus: domain === SENDING ? 'PENDING' : null })
		);
		const { client } = makeClient();

		const result = await activateOperationalDomain({
			client,
			organizationId: ORG,
			rootDomain: ROOT
		});

		expect(result.sending.spf_status).toBe('pending');
		expect(result.sending.lifecycle_state).toBe('verified');
	});

	it('stays pending while DKIM has not verified', async () => {
		vi.mocked(ses.getSesIdentity).mockImplementation(async (domain) =>
			identity(domain, { dkimStatus: 'PENDING', verifiedForSending: false })
		);
		const { client, inserted } = makeClient();

		const result = await activateOperationalDomain({
			client,
			organizationId: ORG,
			rootDomain: ROOT
		});

		expect(result.sending.lifecycle_state).toBe('pending_dns');
		expect(result.receiving.ses_identity_status).toBe('pending');
		expect(inserted[0].verified_at).toBeNull();
		// SES will not receive for an unverified identity, so mail.<root> gets no MX yet.
		expect(writtenRecords().some((record) => record.type === 'MX' && record.name === SENDING)).toBe(
			false
		);
		expect(ses.reconcileSesReceiptRule).not.toHaveBeenCalled();
	});

	it('reuses an existing sending row, keeping its first verification date', async () => {
		const { client, updated, inserted } = makeClient([
			{
				id: 'existing-sending',
				organization_id: ORG,
				purpose: 'sending',
				provider: 'ses',
				domain_name: SENDING,
				lifecycle_state: 'verified',
				verified_at: '2026-08-01T00:00:00.000Z'
			}
		]);

		await activateOperationalDomain({ client, organizationId: ORG, rootDomain: ROOT });

		expect(inserted).toHaveLength(0);
		expect(updated[0]).toMatchObject({
			id: 'existing-sending',
			row: { provider: 'ses', verified_at: '2026-08-01T00:00:00.000Z' }
		});
	});

	it('turns on customer replies in the same pass once the reply identity is verified', async () => {
		const { client } = makeClient([
			{
				id: 'ses-receiving',
				organization_id: ORG,
				purpose: 'receiving',
				provider: 'ses',
				domain_name: RECEIVING,
				lifecycle_state: 'pending_dns'
			}
		]);

		const result = await activateOperationalDomain({
			client,
			organizationId: ORG,
			rootDomain: ROOT
		});

		expect(reconcileReplyIngestion).toHaveBeenCalledWith({
			client,
			organizationId: ORG,
			root: ROOT,
			receiving: RECEIVING,
			zoneId: 'zone-1',
			receivingId: 'ses-receiving'
		});
		expect(result.receiving).toMatchObject({
			domain_id: 'ses-receiving',
			lifecycle_state: 'pending_dns',
			inbound_mx_status: 'pending',
			ses_identity_status: 'passing',
			records_written: 4
		});
	});

	it('does not route replies to SES before the reply identity is verified', async () => {
		vi.mocked(ses.getSesIdentity).mockImplementation(async (domain) =>
			domain === RECEIVING ? identity(domain, { dkimStatus: 'PENDING' }) : identity(domain)
		);
		const { client } = makeClient();

		const result = await activateOperationalDomain({
			client,
			organizationId: ORG,
			rootDomain: ROOT
		});

		expect(reconcileReplyIngestion).not.toHaveBeenCalled();
		expect(result.receiving).toMatchObject({
			domain_id: null,
			lifecycle_state: null,
			ses_identity_status: 'pending'
		});
	});

	it('refuses a reply subdomain that already routes mail somewhere else', async () => {
		vi.mocked(cloudflare.listCloudflareDnsRecords).mockImplementation(async (_zone, name) =>
			name === RECEIVING
				? [
						{
							id: 'mx1',
							type: 'MX',
							name: RECEIVING,
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
			activateOperationalDomain({ client, organizationId: ORG, rootDomain: ROOT })
		).rejects.toMatchObject({ code: 'subdomain_occupied' });
		expect(cloudflare.createCloudflareDnsRecord).not.toHaveBeenCalled();
	});

	it('stops before any provider call when another organization owns the name', async () => {
		const { client } = makeClient([
			{
				id: 'other',
				organization_id: '22222222-2222-2222-2222-222222222222',
				purpose: 'sending',
				domain_name: SENDING,
				lifecycle_state: 'verified'
			}
		]);

		await expect(
			activateOperationalDomain({ client, organizationId: ORG, rootDomain: ROOT })
		).rejects.toBeInstanceOf(EmailDomainActivationError);
		expect(ses.createSesIdentity).not.toHaveBeenCalled();
		expect(cloudflare.resolveCloudflareZone).not.toHaveBeenCalled();
	});
});

describe('recheckOperationalDomain', () => {
	it('re-runs the reconciliation from the recorded root domain', async () => {
		const { client, updated } = makeClient([
			{
				id: 'ses-sending',
				organization_id: ORG,
				purpose: 'sending',
				provider: 'ses',
				domain_name: SENDING,
				dns_zone: ROOT,
				lifecycle_state: 'pending_dns'
			}
		]);

		const result = await recheckOperationalDomain({
			client,
			organizationId: ORG,
			domainId: 'ses-sending'
		});

		expect(result.sending.lifecycle_state).toBe('verified');
		expect(updated[0].id).toBe('ses-sending');
	});
});

describe('teardownOperationalDomain', () => {
	function record(id: string, type: string, name: string, content: string) {
		return { id, type, name, content, ttl: 1, priority: null, proxied: false };
	}

	it('stops receiving first, then deletes only the records UCRM wrote and both identities', async () => {
		const order: string[] = [];
		const zone: Record<string, ReturnType<typeof record>[]> = {
			[RECEIVING]: [
				record('reply-mx', 'MX', RECEIVING, INBOUND_MX),
				record('someone-else', 'TXT', RECEIVING, 'google-site-verification=abc')
			],
			[SENDING]: [record('mail-mx', 'MX', SENDING, INBOUND_MX)],
			[`r1._domainkey.${RECEIVING}`]: [
				record('r1', 'CNAME', `r1._domainkey.${RECEIVING}`, 'r1.dkim.amazonses.com')
			],
			[`s1._domainkey.${SENDING}`]: [
				record('s1', 'CNAME', `s1._domainkey.${SENDING}`, 's1.dkim.amazonses.com')
			],
			[MAIL_FROM]: [
				record('mf-mx', 'MX', MAIL_FROM, MAIL_FROM_MX),
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

		await teardownOperationalDomain({ organizationId: ORG, rootDomain: ROOT });

		// Receiving stops first: the reply MX, then the reply identity SES receives for, before sending.
		// Receiving stops first: both reply MX records go before any identity.
		expect(order.slice(0, 2)).toEqual(['dns:reply-mx', 'dns:mail-mx']);
		expect(order.indexOf(`identity:${RECEIVING}`)).toBeLessThan(
			order.indexOf(`identity:${SENDING}`)
		);
		expect(order).toContain(`identity:${RECEIVING}`);
		expect(order).toContain(`identity:${SENDING}`);
		expect(order).toEqual(expect.arrayContaining(['dns:r1', 'dns:s1', 'dns:mf-mx', 'dns:mf-txt']));
		expect(order).not.toContain('dns:someone-else');
	});
});
