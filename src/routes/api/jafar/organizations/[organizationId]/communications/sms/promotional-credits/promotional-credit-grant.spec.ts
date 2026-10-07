import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

vi.mock('$lib/server/auth/owner', () => ({
	getOwnerSession: vi.fn(),
	consumeOwnerStepUp: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedConsumeStepUp = vi.mocked(consumeOwnerStepUp);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const idempotencyKey = '323e4567-e89b-12d3-a456-426614174000';
const futureExpiry = new Date(Date.now() + 30 * 86_400_000).toISOString();

function session() {
	return {
		email: 'owner@example.com',
		sessionId: 'session-id',
		role: null,
		memberId: null,
		name: null
	};
}

function postEvent(body: unknown, org = organizationId) {
	return {
		params: { organizationId: org },
		request: new Request(
			`http://localhost/api/jafar/organizations/${org}/communications/sms/promotional-credits`,
			{
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			}
		),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function getEvent(org = organizationId) {
	return { params: { organizationId: org }, cookies: {} } as Parameters<typeof GET>[0];
}

function creditListClient(credits: Record<string, unknown>[]) {
	return {
		from: (table: string) => {
			if (table === 'communication_sms_promotional_credits') {
				const builder = {
					select: () => builder,
					eq: () => builder,
					order: () => Promise.resolve({ data: credits, error: null })
				};
				return builder;
			}
			throw new Error(`Unexpected table: ${table}`);
		}
	};
}

function grantClient(rpcResult: {
	data: unknown;
	error: { code: string; message: string } | null;
}) {
	const auditInsert = vi.fn().mockResolvedValue({ error: null });
	return {
		from: (table: string) => {
			if (table === 'access_audit_events') return { insert: auditInsert };
			throw new Error(`Unexpected table: ${table}`);
		},
		rpc: vi.fn().mockResolvedValue(rpcResult),
		auditInsert
	};
}

function validBody() {
	return {
		amount_minor: 500,
		expires_at: futureExpiry,
		reason: 'welcome credit',
		idempotency_key: idempotencyKey
	};
}

describe('platform owner SMS promotional-credit read', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await GET(getEvent());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('lists this organization credits only', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = creditListClient([
			{ id: 'credit-1', status: 'active' },
			{ id: 'credit-2', status: 'revoked' }
		]);
		mockedClient.mockReturnValue(client as never);

		const response = await GET(getEvent());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.credits).toHaveLength(2);
		expect(body.credits[0]).toMatchObject({ id: 'credit-1', status: 'active' });
	});
});

describe('platform owner SMS promotional-credit grant boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects a past expiry before database access', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await POST(
			postEvent({ ...validBody(), expires_at: new Date(Date.now() - 86_400_000).toISOString() })
		);

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires password reconfirmation before granting credit', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(403);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('grants credit with the platform-owner sentinel actor and audits a genuinely new grant', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = grantClient({
			data: [{ id: 'credit-1', status: 'active', applied: true }],
			error: null
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_grant_promotional_credit',
			expect.objectContaining({
				p_organization_id: organizationId,
				p_amount_minor: 500,
				p_idempotency_key: idempotencyKey,
				p_granted_by: PLATFORM_OWNER_ACTOR_ID
			})
		);
		expect(client.auditInsert).toHaveBeenCalledTimes(1);
	});

	it('never audits a replayed grant (same idempotency key)', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = grantClient({
			data: [{ id: 'credit-1', status: 'active', applied: false }],
			error: null
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(200);
		expect(client.auditInsert).not.toHaveBeenCalled();
	});

	it('translates a database rule violation into a conflict', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = grantClient({
			data: null,
			error: { code: 'P0001', message: 'a promotional grant must record an idempotency key' }
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(409);
	});
});
