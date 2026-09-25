import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { activateReplyIngestion, ReplyIngestionNotReadyError } from './operational-reply-ingestion';

vi.mock('./ses', async () => {
	const actual = await vi.importActual<typeof import('./ses')>('./ses');
	return {
		...actual,
		getSesIdentity: vi.fn(),
		reconcileSesReceiptRule: vi.fn(),
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

const resolveMx = vi.fn();
vi.mock('node:dns/promises', () => ({
	Resolver: class {
		setServers() {}
		resolveMx = resolveMx;
	}
}));

import * as ses from './ses';
import * as cloudflare from './cloudflare-dns';

const ORG = '11111111-1111-1111-1111-111111111111';
const ROOT = 'contractor.com';
const RECEIVING = 'reply.contractor.com';
const INBOUND_MX = 'inbound-smtp.us-east-1.amazonaws.com';

type DomainRow = {
	id: string;
	organization_id: string;
	purpose: string;
	lifecycle_state: string;
	domain_name?: string;
	verified_at?: string | null;
};

// Mirrors operational-domain-activation.spec.ts's fake owner client exactly.
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

function verifiedIdentity(): ses.SesIdentity {
	return {
		verifiedForSending: true,
		dkimStatus: 'SUCCESS',
		dkimSigningEnabled: true,
		dkimTokens: ['r1', 'r2', 'r3'],
		mailFromDomain: null,
		mailFromStatus: null
	};
}

let mxAnswers: Record<string, string[]>;

beforeEach(() => {
	vi.clearAllMocks();
	mxAnswers = {};
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
	vi.mocked(ses.getSesIdentity).mockResolvedValue(verifiedIdentity());
	vi.mocked(ses.sesInboundMxTarget).mockReturnValue(INBOUND_MX);
	vi.mocked(ses.reconcileSesReceiptRule).mockResolvedValue(undefined);
	resolveMx.mockImplementation(async (domain: string) =>
		(mxAnswers[domain] ?? []).map((exchange) => ({ exchange, priority: 10 }))
	);
});

describe('activateReplyIngestion', () => {
	it('refuses to run before the reply subdomain is a verified SES identity', async () => {
		vi.mocked(ses.getSesIdentity).mockResolvedValue(null);
		const { client } = makeClient();

		await expect(
			activateReplyIngestion({ client, organizationId: ORG, rootDomain: ROOT })
		).rejects.toBeInstanceOf(ReplyIngestionNotReadyError);
		expect(ses.reconcileSesReceiptRule).not.toHaveBeenCalled();
		expect(cloudflare.createCloudflareDnsRecord).not.toHaveBeenCalled();
	});

	it('creates the receipt rule before writing the MX record', async () => {
		const { client } = makeClient();
		const order: string[] = [];
		vi.mocked(ses.reconcileSesReceiptRule).mockImplementation(async () => {
			order.push('rule');
		});
		vi.mocked(cloudflare.createCloudflareDnsRecord).mockImplementation(async (_zone, input) => {
			order.push('mx');
			return {
				id: 'cf-new',
				type: input.type,
				name: input.name,
				content: input.content,
				ttl: 1,
				priority: input.priority ?? null,
				proxied: false
			};
		});

		await activateReplyIngestion({ client, organizationId: ORG, rootDomain: ROOT });

		expect(order).toEqual(['rule', 'mx']);
		expect(ses.reconcileSesReceiptRule).toHaveBeenCalledWith(
			'ucrm-ses-inbound-rules',
			`reply-${ORG}`,
			RECEIVING,
			expect.objectContaining({ objectKeyPrefix: `${ORG}/` })
		);
	});

	it('never reads or writes outside the reply subdomain', async () => {
		const { client } = makeClient();

		await activateReplyIngestion({ client, organizationId: ORG, rootDomain: ROOT });

		const written = vi
			.mocked(cloudflare.createCloudflareDnsRecord)
			.mock.calls.map(([, input]) => input.name);
		const inspected = vi
			.mocked(cloudflare.listCloudflareDnsRecords)
			.mock.calls.map(([, name]) => name);
		for (const name of [...written, ...inspected]) {
			expect(name === RECEIVING || name.endsWith(`.${RECEIVING}`)).toBe(true);
		}
	});

	it('allows the pre-existing Brevo inbound targets without treating the subdomain as occupied', async () => {
		vi.mocked(cloudflare.listCloudflareDnsRecords).mockResolvedValue([
			{
				id: 'cf-1',
				type: 'MX',
				name: RECEIVING,
				content: 'inbound1.sendinblue.com',
				ttl: 1,
				priority: 10,
				proxied: false
			}
		]);
		const { client } = makeClient();

		await expect(
			activateReplyIngestion({ client, organizationId: ORG, rootDomain: ROOT })
		).resolves.toBeDefined();
	});

	it('refuses an MX already pointed at an unrelated third party', async () => {
		vi.mocked(cloudflare.listCloudflareDnsRecords).mockResolvedValue([
			{
				id: 'cf-1',
				type: 'MX',
				name: RECEIVING,
				content: 'mx.some-other-provider.example',
				ttl: 1,
				priority: 10,
				proxied: false
			}
		]);
		const { client } = makeClient();

		await expect(
			activateReplyIngestion({ client, organizationId: ORG, rootDomain: ROOT })
		).rejects.toThrow();
	});

	it('reports pending_dns until public DNS actually answers with the SES inbound target', async () => {
		const { client, inserted } = makeClient();

		const result = await activateReplyIngestion({ client, organizationId: ORG, rootDomain: ROOT });

		expect(result.inbound_mx_status).toBe('pending');
		expect(result.lifecycle_state).toBe('pending_dns');
		expect(inserted[0].lifecycle_state).toBe('pending_dns');
		expect(inserted[0].purpose).toBe('receiving');
		expect(inserted[0].provider).toBe('ses');
	});

	it('reports verified once public DNS answers with the SES inbound target', async () => {
		mxAnswers[RECEIVING] = [INBOUND_MX];
		const { client, inserted } = makeClient();

		const result = await activateReplyIngestion({ client, organizationId: ORG, rootDomain: ROOT });

		expect(result.inbound_mx_status).toBe('passing');
		expect(result.lifecycle_state).toBe('verified');
		expect(inserted[0].verified_at).toBeTruthy();
	});

	it('a domain verified once stays unhealthy rather than reverting to pending_dns if the MX later disappears', async () => {
		const { client, updated } = makeClient([
			{
				id: 'domain-existing',
				organization_id: ORG,
				purpose: 'receiving',
				domain_name: RECEIVING,
				lifecycle_state: 'verified',
				verified_at: '2026-01-01T00:00:00.000Z'
			}
		]);

		const result = await activateReplyIngestion({ client, organizationId: ORG, rootDomain: ROOT });

		expect(result.lifecycle_state).toBe('unhealthy');
		expect(updated[0].row.verified_at).toBe('2026-01-01T00:00:00.000Z');
	});
});
