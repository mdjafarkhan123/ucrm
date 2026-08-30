import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { activateEmailDomain, EmailDomainActivationError } from './email-domain-activation';
import { BrevoManagementError } from './brevo';

vi.mock('./brevo', async () => {
	const actual = await vi.importActual<typeof import('./brevo')>('./brevo');
	return {
		...actual,
		getBrevoDomain: vi.fn(),
		createBrevoDomain: vi.fn(),
		listBrevoDomains: vi.fn(),
		authenticateBrevoDomain: vi.fn(),
		listBrevoInboundWebhooks: vi.fn(),
		createBrevoInboundWebhook: vi.fn()
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

import * as brevo from './brevo';
import * as cloudflare from './cloudflare-dns';

const ORG = '11111111-1111-1111-1111-111111111111';
const ROOT = 'contractor.com';
const WEBHOOK_URL = 'https://app.example.com/api/webhooks/brevo/inbound';

type DomainRow = {
	id: string;
	organization_id: string;
	purpose: string;
	lifecycle_state: string;
};

/**
 * Minimal fake of the owner Supabase client for the communication_email_domains table only. Records the
 * rows the reconciler inserts/updates and answers the existing-domain lookup from a preset map.
 */
function makeClient(existingByName: Record<string, DomainRow> = {}) {
	const inserted: Record<string, unknown>[] = [];
	const updated: { id: string; row: Record<string, unknown> }[] = [];
	let idSeq = 0;

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
				const match = existingByName[String(filters.domain_name)];
				return Promise.resolve({ data: match ?? null, error: null });
			},
			single: () => {
				idSeq += 1;
				const id = `domain-${idSeq}`;
				inserted.push({ id, ...payload });
				return Promise.resolve({ data: { id }, error: null });
			}
		};
		return builder;
	};

	return {
		client: { from } as unknown as SupabaseClient<Database>,
		inserted,
		updated
	};
}

function brevoConfig(overrides: Partial<brevo.BrevoDomainConfiguration> = {}) {
	return {
		domain: 'unused',
		verified: true,
		authenticated: true,
		dns_records: [],
		...overrides
	} satisfies brevo.BrevoDomainConfiguration;
}

beforeEach(() => {
	vi.clearAllMocks();
	vi.mocked(cloudflare.resolveCloudflareZone).mockResolvedValue({
		id: 'zone-1',
		name: 'contractor.com'
	});
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
	vi.mocked(cloudflare.updateCloudflareDnsRecord).mockImplementation(async (_zone, id, input) => ({
		id,
		type: input.type,
		name: input.name,
		content: input.content,
		ttl: 1,
		priority: input.priority ?? null,
		proxied: false
	}));
	vi.mocked(brevo.listBrevoDomains).mockImplementation(async () => [
		{ id: 'brevo-mail', domain_name: 'mail.contractor.com', verified: true, authenticated: true },
		{ id: 'brevo-reply', domain_name: 'reply.contractor.com', verified: true, authenticated: false }
	]);
	vi.mocked(brevo.authenticateBrevoDomain).mockResolvedValue(undefined);
	vi.mocked(brevo.listBrevoInboundWebhooks).mockResolvedValue([]);
	vi.mocked(brevo.createBrevoInboundWebhook).mockResolvedValue({
		id: 4242,
		url: WEBHOOK_URL,
		type: 'inbound',
		domain: 'reply.contractor.com',
		events: ['inboundEmailProcessed']
	});
});

describe('managed email-domain activation', () => {
	it('derives both subdomains, writes their records, verifies, and registers one inbound webhook', async () => {
		vi.mocked(brevo.getBrevoDomain).mockImplementation(async (name: string) => {
			if (name === 'mail.contractor.com') {
				return brevoConfig({
					dns_records: [
						{
							type: 'TXT',
							host_name: 'mail.contractor.com',
							value: 'brevo-code:abc',
							status: true
						},
						{
							type: 'CNAME',
							host_name: 'brevo1._domainkey.mail.contractor.com',
							value: 'b1.dkim.brevo.com',
							status: true
						}
					]
				});
			}
			return brevoConfig({
				verified: true,
				authenticated: false,
				dns_records: [
					{
						type: 'TXT',
						host_name: 'reply.contractor.com',
						value: 'brevo-code:xyz',
						status: true
					}
				]
			});
		});

		const { client, inserted } = makeClient();
		const result = await activateEmailDomain({
			client,
			organizationId: ORG,
			rootDomain: ROOT,
			webhookUrl: WEBHOOK_URL
		});

		expect(result.sending.domain_name).toBe('mail.contractor.com');
		expect(result.receiving.domain_name).toBe('reply.contractor.com');
		expect(result.zone_id).toBe('zone-1');

		// Sending: fully ready -> verified with the passing statuses the constraint requires.
		expect(result.sending.lifecycle_state).toBe('verified');
		expect(result.sending.provider_authenticated).toBe(true);
		expect(result.sending.ownership_status).toBe('passing');
		expect(result.sending.dkim_status).toBe('passing');

		// Receiving: the two documented inbound MX records were written on reply.contractor.com.
		const mxCalls = vi
			.mocked(cloudflare.createCloudflareDnsRecord)
			.mock.calls.filter(([, input]) => input.type === 'MX');
		expect(mxCalls.map(([, input]) => input.content).sort()).toEqual([
			'inbound1.sendinblue.com',
			'inbound2.sendinblue.com'
		]);
		expect(mxCalls.every(([, input]) => input.proxied === false)).toBe(true);

		// Exactly one webhook, its id stored on the receiving row.
		expect(brevo.createBrevoInboundWebhook).toHaveBeenCalledTimes(1);
		expect(result.receiving.provider_inbound_webhook_id).toBe('4242');

		// The receiving row honors purpose_health_check: authenticated=false, dkim unchecked.
		const receivingRow = inserted.find((row) => row.purpose === 'receiving');
		expect(receivingRow).toMatchObject({
			provider_authenticated: false,
			dkim_status: 'unchecked',
			dmarc_status: 'unchecked',
			spf_status: 'unchecked',
			inbound_mx_status: 'passing',
			provider_inbound_webhook_id: '4242'
		});

		// Both subdomains are nudged to verify: sending authenticates DKIM, receiving validates ownership so
		// its inbound webhook can attach. The receiving row stays non-sending regardless (asserted above).
		expect(brevo.authenticateBrevoDomain).toHaveBeenCalledWith('mail.contractor.com');
		expect(brevo.authenticateBrevoDomain).toHaveBeenCalledWith('reply.contractor.com');
	});

	it('is idempotent on a receiving Recheck: re-triggers verification, reuses the one webhook, stays verified', async () => {
		// Domain already verified and its single inbound webhook already present. A Recheck must not duplicate
		// anything: the verification nudge is fired again (harmless/idempotent) but no second webhook is made.
		vi.mocked(brevo.getBrevoDomain).mockImplementation(async (name: string) => {
			if (name === 'reply.contractor.com') {
				return brevoConfig({
					verified: true,
					authenticated: false,
					dns_records: [
						{
							type: 'TXT',
							host_name: 'reply.contractor.com',
							value: 'brevo-code:xyz',
							status: true
						}
					]
				});
			}
			return brevoConfig({ dns_records: [] });
		});
		vi.mocked(brevo.listBrevoInboundWebhooks).mockResolvedValue([
			{
				id: 9001,
				url: WEBHOOK_URL,
				type: 'inbound',
				domain: 'reply.contractor.com',
				events: ['inboundEmailProcessed']
			}
		]);

		const { client } = makeClient();
		const result = await activateEmailDomain({
			client,
			organizationId: ORG,
			rootDomain: ROOT,
			webhookUrl: WEBHOOK_URL
		});

		expect(brevo.authenticateBrevoDomain).toHaveBeenCalledWith('reply.contractor.com');
		expect(brevo.createBrevoInboundWebhook).not.toHaveBeenCalled();
		expect(result.receiving.provider_inbound_webhook_id).toBe('9001');
		expect(result.receiving.lifecycle_state).toBe('verified');
	});

	it('leaves the receiving domain pending when Brevo cannot yet verify it', async () => {
		// The verification nudge is refused with a 400 (records not resolvable to Brevo yet). That is a
		// pending, not failed, state: no throw, the row stays pending_dns with a null webhook for a Recheck.
		vi.mocked(brevo.getBrevoDomain).mockImplementation(async (name: string) => {
			if (name === 'reply.contractor.com') {
				return brevoConfig({
					verified: false,
					authenticated: false,
					dns_records: [
						{
							type: 'TXT',
							host_name: 'reply.contractor.com',
							value: 'brevo-code:xyz',
							status: true
						}
					]
				});
			}
			return brevoConfig({ dns_records: [] });
		});
		vi.mocked(brevo.authenticateBrevoDomain).mockImplementation(async (name: string) => {
			if (name === 'reply.contractor.com') {
				throw new BrevoManagementError('not ready', 400, 'brevo_http_400');
			}
			return undefined;
		});
		// An unverified domain also refuses the webhook with its specific not-active 400 -> null webhook id.
		vi.mocked(brevo.createBrevoInboundWebhook).mockRejectedValue(
			new BrevoManagementError(
				'Brevo rejected the domain-management request with status 400: Domain is not found or is inactive.',
				400,
				'brevo_http_400',
				'invalid_parameter',
				'Domain is not found or is inactive'
			)
		);

		const { client } = makeClient();
		const result = await activateEmailDomain({
			client,
			organizationId: ORG,
			rootDomain: ROOT,
			webhookUrl: WEBHOOK_URL
		});

		expect(brevo.authenticateBrevoDomain).toHaveBeenCalledWith('reply.contractor.com');
		expect(result.receiving.lifecycle_state).toBe('pending_dns');
		expect(result.receiving.provider_verified).toBe(false);
		expect(result.receiving.provider_inbound_webhook_id).toBeNull();
	});

	it('surfaces an unexpected Brevo failure while verifying the receiving domain', async () => {
		vi.mocked(brevo.getBrevoDomain).mockResolvedValue(brevoConfig({ dns_records: [] }));
		vi.mocked(brevo.authenticateBrevoDomain).mockImplementation(async (name: string) => {
			if (name === 'reply.contractor.com') {
				throw new BrevoManagementError('server error', 500, 'brevo_http_500');
			}
			return undefined;
		});

		const { client } = makeClient();
		await expect(
			activateEmailDomain({
				client,
				organizationId: ORG,
				rootDomain: ROOT,
				webhookUrl: WEBHOOK_URL
			})
		).rejects.toBeInstanceOf(BrevoManagementError);
	});

	it('confines every DNS read and write to the derived subdomains, never the parent zone or root', async () => {
		// A managed subdomain root: the Cloudflare zone is the parent (upliftcontractor.com), but activation
		// must only ever touch mail.test.upliftcontractor.com / reply.test.upliftcontractor.com. The existing
		// root MX at test.upliftcontractor.com and any parent records must be neither read nor written.
		const SUB_ROOT = 'test.upliftcontractor.com';
		const SENDING = 'mail.test.upliftcontractor.com';
		const RECEIVING = 'reply.test.upliftcontractor.com';

		// The Cloudflare zone is the parent apex, not the subdomain root.
		vi.mocked(cloudflare.resolveCloudflareZone).mockResolvedValue({
			id: 'zone-1',
			name: 'upliftcontractor.com'
		});
		vi.mocked(brevo.listBrevoDomains).mockResolvedValue([
			{ id: 'brevo-mail', domain_name: SENDING, verified: true, authenticated: true },
			{ id: 'brevo-reply', domain_name: RECEIVING, verified: true, authenticated: false }
		]);
		vi.mocked(brevo.getBrevoDomain).mockImplementation(async (name: string) => {
			if (name === SENDING) {
				return brevoConfig({
					dns_records: [
						{ type: 'TXT', host_name: SENDING, value: 'brevo-code:abc', status: true },
						{
							type: 'CNAME',
							host_name: `brevo1._domainkey.${SENDING}`,
							value: 'b1.dkim.brevo.com',
							status: true
						}
					]
				});
			}
			return brevoConfig({ verified: true, authenticated: false, dns_records: [] });
		});

		const { client } = makeClient();
		await activateEmailDomain({
			client,
			organizationId: ORG,
			rootDomain: SUB_ROOT,
			webhookUrl: WEBHOOK_URL
		});

		const underManagedSubdomain = (name: string) =>
			name === SENDING ||
			name === RECEIVING ||
			name.endsWith(`.${SENDING}`) ||
			name.endsWith(`.${RECEIVING}`);

		// Every record LIST is scoped to a managed subdomain -- the root/parent are never even queried.
		const listedNames = vi
			.mocked(cloudflare.listCloudflareDnsRecords)
			.mock.calls.map(([, name]) => name);
		expect(listedNames.length).toBeGreaterThan(0);
		for (const name of listedNames) {
			expect(underManagedSubdomain(name)).toBe(true);
			expect(name).not.toBe(SUB_ROOT);
			expect(name).not.toBe('upliftcontractor.com');
		}

		// Every record CREATE/UPDATE targets a managed subdomain; nothing is written at the root or parent.
		const writtenNames = [
			...vi.mocked(cloudflare.createCloudflareDnsRecord).mock.calls,
			...vi.mocked(cloudflare.updateCloudflareDnsRecord).mock.calls
		].map((call) => call[call.length - 1] as { name: string });
		expect(writtenNames.length).toBeGreaterThan(0);
		for (const input of writtenNames) {
			expect(underManagedSubdomain(input.name)).toBe(true);
			expect(input.name).not.toBe(SUB_ROOT);
			expect(input.name).not.toBe('upliftcontractor.com');
		}
	});

	it("fully-qualifies Brevo's mixed zone-relative and domain-relative host names", async () => {
		// The real Brevo API shortens host names: verification/DMARC relative to the ZONE apex, but DKIM
		// (_domainkey) relative to the DOMAIN. Both must land at their correct fully-qualified names.
		vi.mocked(brevo.getBrevoDomain).mockImplementation(async (name: string) => {
			if (name === 'mail.contractor.com') {
				return brevoConfig({
					dns_records: [
						// Zone-relative apex ownership TXT.
						{ type: 'TXT', host_name: 'mail', value: 'brevo-code:abc', status: true },
						// Zone-relative DMARC.
						{ type: 'TXT', host_name: '_dmarc.mail', value: 'v=DMARC1; p=none', status: true },
						// Domain-relative DKIM CNAMEs (the ones that broke the live run).
						{
							type: 'CNAME',
							host_name: 'brevo1._domainkey',
							value: 'b1.dkim.brevo.com',
							status: true
						},
						{
							type: 'CNAME',
							host_name: 'brevo2._domainkey',
							value: 'b2.dkim.brevo.com',
							status: true
						}
					]
				});
			}
			return brevoConfig({ verified: true, authenticated: false, dns_records: [] });
		});

		const { client } = makeClient();
		await activateEmailDomain({
			client,
			organizationId: ORG,
			rootDomain: ROOT, // contractor.com -> zone name 'contractor.com'
			webhookUrl: WEBHOOK_URL
		});

		const created = vi
			.mocked(cloudflare.createCloudflareDnsRecord)
			.mock.calls.map(([, input]) => ({ type: input.type, name: input.name }));

		// Ownership + DMARC expanded against the zone apex; DKIM expanded against the sending domain.
		expect(created).toEqual(
			expect.arrayContaining([
				{ type: 'TXT', name: 'mail.contractor.com' },
				{ type: 'TXT', name: '_dmarc.mail.contractor.com' },
				{ type: 'CNAME', name: 'brevo1._domainkey.mail.contractor.com' },
				{ type: 'CNAME', name: 'brevo2._domainkey.mail.contractor.com' }
			])
		);
		// Nothing was placed at the bare zone apex (the collision the domain-relative DKIM rule prevents).
		for (const record of created) {
			expect(record.name).not.toBe('brevo1._domainkey.contractor.com');
			expect(record.name).not.toBe('brevo2._domainkey.contractor.com');
		}
	});

	it('holds the receiving webhook pending when Brevo says the domain is not active, then a Recheck creates it', async () => {
		// Ownership is in place, but Brevo has not yet activated the domain, so the first webhook create is
		// refused with its specific 400. A later Recheck, once Brevo has verified the domain, succeeds.
		vi.mocked(brevo.getBrevoDomain).mockImplementation(async (name: string) => {
			if (name === 'reply.contractor.com') {
				return brevoConfig({
					verified: true,
					authenticated: false,
					dns_records: [
						{
							type: 'TXT',
							host_name: 'reply.contractor.com',
							value: 'brevo-code:xyz',
							status: true
						}
					]
				});
			}
			return brevoConfig({ dns_records: [] });
		});
		vi.mocked(brevo.createBrevoInboundWebhook)
			.mockRejectedValueOnce(
				new BrevoManagementError(
					'Brevo rejected the domain-management request with status 400: Domain is not found or is inactive.',
					400,
					'brevo_http_400',
					'invalid_parameter',
					'Domain is not found or is inactive'
				)
			)
			.mockResolvedValueOnce({
				id: 4242,
				url: WEBHOOK_URL,
				type: 'inbound',
				domain: 'reply.contractor.com',
				events: ['inboundEmailProcessed']
			});

		const { client, inserted } = makeClient();

		// Pass 1 — the webhook cannot be attached yet: the row persists pending with a null webhook id.
		const first = await activateEmailDomain({
			client,
			organizationId: ORG,
			rootDomain: ROOT,
			webhookUrl: WEBHOOK_URL
		});
		expect(first.receiving.provider_inbound_webhook_id).toBeNull();
		expect(first.receiving.lifecycle_state).toBe('pending_dns');
		expect(inserted.find((row) => row.purpose === 'receiving')).toMatchObject({
			provider_inbound_webhook_id: null,
			lifecycle_state: 'pending_dns'
		});

		// Pass 2 (Recheck) — the domain is active now, so exactly one webhook is created and the row verifies.
		const second = await activateEmailDomain({
			client,
			organizationId: ORG,
			rootDomain: ROOT,
			webhookUrl: WEBHOOK_URL
		});
		expect(second.receiving.provider_inbound_webhook_id).toBe('4242');
		expect(second.receiving.lifecycle_state).toBe('verified');
	});

	it('surfaces an unrelated webhook 400 as a real failure instead of treating it as pending', async () => {
		vi.mocked(brevo.getBrevoDomain).mockResolvedValue(brevoConfig({ dns_records: [] }));
		// Same status and provider code, but a different condition -- it must NOT be swallowed as pending.
		vi.mocked(brevo.createBrevoInboundWebhook).mockRejectedValue(
			new BrevoManagementError(
				'Brevo rejected the domain-management request with status 400: Webhook url is invalid.',
				400,
				'brevo_http_400',
				'invalid_parameter',
				'Webhook url is invalid'
			)
		);

		const { client } = makeClient();
		await expect(
			activateEmailDomain({
				client,
				organizationId: ORG,
				rootDomain: ROOT,
				webhookUrl: WEBHOOK_URL
			})
		).rejects.toBeInstanceOf(BrevoManagementError);
	});

	it('reuses an existing inbound webhook rather than creating a second', async () => {
		vi.mocked(brevo.getBrevoDomain).mockResolvedValue(brevoConfig({ dns_records: [] }));
		vi.mocked(brevo.listBrevoInboundWebhooks).mockResolvedValue([
			{
				id: 9001,
				url: WEBHOOK_URL,
				type: 'inbound',
				domain: 'reply.contractor.com',
				events: ['inboundEmailProcessed']
			}
		]);

		const { client } = makeClient();
		const result = await activateEmailDomain({
			client,
			organizationId: ORG,
			rootDomain: ROOT,
			webhookUrl: WEBHOOK_URL
		});

		expect(brevo.createBrevoInboundWebhook).not.toHaveBeenCalled();
		expect(result.receiving.provider_inbound_webhook_id).toBe('9001');
	});

	it('updates an existing sending row instead of inserting a duplicate', async () => {
		vi.mocked(brevo.getBrevoDomain).mockResolvedValue(brevoConfig({ dns_records: [] }));
		const { client, inserted, updated } = makeClient({
			'mail.contractor.com': {
				id: 'existing-send',
				organization_id: ORG,
				purpose: 'sending',
				lifecycle_state: 'pending_dns'
			}
		});

		await activateEmailDomain({
			client,
			organizationId: ORG,
			rootDomain: ROOT,
			webhookUrl: WEBHOOK_URL
		});

		expect(updated.some((entry) => entry.id === 'existing-send')).toBe(true);
		expect(inserted.some((row) => row.purpose === 'sending')).toBe(false);
	});

	it('refuses to overwrite a sending subdomain that already serves another service', async () => {
		vi.mocked(brevo.getBrevoDomain).mockResolvedValue(brevoConfig({ dns_records: [] }));
		vi.mocked(cloudflare.listCloudflareDnsRecords).mockImplementation(async (_zone, name) => {
			if (name === 'mail.contractor.com') {
				return [
					{
						id: 'cf-a',
						type: 'A',
						name: 'mail.contractor.com',
						content: '203.0.113.9',
						ttl: 1,
						priority: null,
						proxied: false
					}
				];
			}
			return [];
		});

		const { client } = makeClient();
		await expect(
			activateEmailDomain({
				client,
				organizationId: ORG,
				rootDomain: ROOT,
				webhookUrl: WEBHOOK_URL
			})
		).rejects.toMatchObject({ code: 'subdomain_occupied' });
		expect(cloudflare.createCloudflareDnsRecord).not.toHaveBeenCalled();
	});

	it('refuses a receiving subdomain that already routes mail elsewhere', async () => {
		vi.mocked(brevo.getBrevoDomain).mockResolvedValue(brevoConfig({ dns_records: [] }));
		vi.mocked(cloudflare.listCloudflareDnsRecords).mockImplementation(async (_zone, name) => {
			if (name === 'reply.contractor.com') {
				return [
					{
						id: 'cf-mx',
						type: 'MX',
						name: 'reply.contractor.com',
						content: 'mail.othermailhost.com',
						ttl: 1,
						priority: 10,
						proxied: false
					}
				];
			}
			return [];
		});

		const { client } = makeClient();
		await expect(
			activateEmailDomain({
				client,
				organizationId: ORG,
				rootDomain: ROOT,
				webhookUrl: WEBHOOK_URL
			})
		).rejects.toMatchObject({ code: 'subdomain_occupied' });
	});

	it('refuses a Brevo record whose host name escapes the managed subdomain', async () => {
		vi.mocked(brevo.getBrevoDomain).mockImplementation(async (name: string) => {
			if (name === 'mail.contractor.com') {
				return brevoConfig({
					dns_records: [
						{ type: 'TXT', host_name: 'contractor.com', value: 'brevo-code:root', status: true }
					]
				});
			}
			return brevoConfig({ dns_records: [] });
		});

		const { client } = makeClient();
		await expect(
			activateEmailDomain({
				client,
				organizationId: ORG,
				rootDomain: ROOT,
				webhookUrl: WEBHOOK_URL
			})
		).rejects.toMatchObject({ code: 'record_outside_subdomain' });
	});

	it('rejects an invalid root domain before any provider call', async () => {
		const { client } = makeClient();
		await expect(
			activateEmailDomain({
				client,
				organizationId: ORG,
				rootDomain: 'not a domain',
				webhookUrl: WEBHOOK_URL
			})
		).rejects.toMatchObject({ code: 'invalid_root_domain' });
		expect(cloudflare.resolveCloudflareZone).not.toHaveBeenCalled();
	});

	it('leaves the sending domain pending when Brevo cannot yet authenticate it', async () => {
		vi.mocked(brevo.getBrevoDomain).mockImplementation(async (name: string) => {
			if (name === 'mail.contractor.com') {
				return brevoConfig({
					verified: true,
					authenticated: false,
					dns_records: [
						{ type: 'TXT', host_name: 'mail.contractor.com', value: 'brevo-code:abc', status: true }
					]
				});
			}
			return brevoConfig({ dns_records: [] });
		});
		vi.mocked(brevo.authenticateBrevoDomain).mockRejectedValue(
			new BrevoManagementError('not ready', 400, 'brevo_http_400')
		);

		const { client } = makeClient();
		const result = await activateEmailDomain({
			client,
			organizationId: ORG,
			rootDomain: ROOT,
			webhookUrl: WEBHOOK_URL
		});

		expect(result.sending.lifecycle_state).toBe('pending_dns');
		expect(result.sending.provider_authenticated).toBe(false);
	});

	it('surfaces an unexpected Brevo authentication failure instead of swallowing it', async () => {
		vi.mocked(brevo.getBrevoDomain).mockResolvedValue(brevoConfig({ dns_records: [] }));
		vi.mocked(brevo.authenticateBrevoDomain).mockRejectedValue(
			new BrevoManagementError('server error', 500, 'brevo_http_500')
		);

		const { client } = makeClient();
		await expect(
			activateEmailDomain({
				client,
				organizationId: ORG,
				rootDomain: ROOT,
				webhookUrl: WEBHOOK_URL
			})
		).rejects.toBeInstanceOf(BrevoManagementError);
	});
});
