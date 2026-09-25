import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	activateOperationalDomain,
	recheckOperationalDomain
} from './operational-domain-activation';
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
		sesIdentityArn: vi.fn(),
		sesConfigurationSetArn: vi.fn(),
		sesMailFromMxTarget: vi.fn(),
		sesInboundMxTarget: vi.fn()
	};
});

vi.mock('./cloudflare-dns', async () => {
	const actual = await vi.importActual<typeof import('./cloudflare-dns')>('./cloudflare-dns');
	return {
		...actual,
		resolveCloudflareZone: vi.fn(),
		listCloudflareDnsRecords: vi.fn(),
		createCloudflareDnsRecord: vi.fn(),
		updateCloudflareDnsRecord: vi.fn()
	};
});

import * as ses from './ses';
import * as cloudflare from './cloudflare-dns';

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
});

describe('activateOperationalDomain', () => {
	it('writes DKIM for both identities plus the MAIL FROM records, and no reply MX', async () => {
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
			}))
		]);
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
	});

	it('moves an existing Brevo sending row onto SES, keeping its first verification date', async () => {
		const { client, updated, inserted } = makeClient([
			{
				id: 'brevo-sending',
				organization_id: ORG,
				purpose: 'sending',
				provider: 'brevo',
				domain_name: SENDING,
				lifecycle_state: 'verified',
				verified_at: '2026-08-01T00:00:00.000Z'
			}
		]);

		await activateOperationalDomain({ client, organizationId: ORG, rootDomain: ROOT });

		expect(inserted).toHaveLength(0);
		expect(updated[0]).toMatchObject({
			id: 'brevo-sending',
			row: { provider: 'ses', verified_at: '2026-08-01T00:00:00.000Z' }
		});
	});

	it('leaves the receiving row and its Brevo reply route untouched', async () => {
		vi.mocked(cloudflare.listCloudflareDnsRecords).mockImplementation(async (_zone, name) =>
			name === RECEIVING
				? [
						{
							id: 'mx1',
							type: 'MX',
							name: RECEIVING,
							content: 'inbound1.sendinblue.com',
							ttl: 1,
							priority: 10,
							proxied: false
						}
					]
				: []
		);
		const { client, updated } = makeClient([
			{
				id: 'brevo-receiving',
				organization_id: ORG,
				purpose: 'receiving',
				provider: 'brevo',
				domain_name: RECEIVING,
				lifecycle_state: 'verified',
				inbound_mx_status: 'passing'
			}
		]);

		const result = await activateOperationalDomain({
			client,
			organizationId: ORG,
			rootDomain: ROOT
		});

		expect(updated.map((write) => write.id)).not.toContain('brevo-receiving');
		expect(
			writtenRecords().some((record) => record.type === 'MX' && record.name === RECEIVING)
		).toBe(false);
		expect(result.receiving).toMatchObject({
			domain_id: 'brevo-receiving',
			lifecycle_state: 'verified',
			inbound_mx_status: 'passing',
			ses_identity_status: 'passing'
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

	it('refuses a row that is still on Brevo', async () => {
		const { client } = makeClient([
			{
				id: 'brevo-sending',
				organization_id: ORG,
				purpose: 'sending',
				provider: 'brevo',
				domain_name: SENDING,
				dns_zone: ROOT,
				lifecycle_state: 'verified'
			}
		]);

		await expect(
			recheckOperationalDomain({ client, organizationId: ORG, domainId: 'brevo-sending' })
		).rejects.toMatchObject({ code: 'operational_domain_not_found' });
	});
});
