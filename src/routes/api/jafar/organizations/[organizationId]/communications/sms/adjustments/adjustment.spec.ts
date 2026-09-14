import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
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

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function postEvent(body: unknown, org = organizationId) {
	return {
		params: { organizationId: org },
		request: new Request(
			`http://localhost/api/jafar/organizations/${org}/communications/sms/adjustments`,
			{
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			}
		),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function adjustmentClient(rpcResult: {
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
	return { amount_minor: 1500, reason: 'goodwill correction', idempotency_key: idempotencyKey };
}

describe('platform owner SMS adjustment boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects a zero amount before database access', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await POST(postEvent({ ...validBody(), amount_minor: 0 }));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires password reconfirmation before recording an adjustment', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(403);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('accepts a negative adjustment amount', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = adjustmentClient({
			data: [{ id: 'entry-1', entry_kind: 'adjustment', amount_minor: -500, applied: true }],
			error: null
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ ...validBody(), amount_minor: -500 }));

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_record_adjustment',
			expect.objectContaining({ p_amount_minor: -500 })
		);
	});

	it('records an adjustment with the platform-owner sentinel actor and audits a genuinely new post', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = adjustmentClient({
			data: [{ id: 'entry-1', entry_kind: 'adjustment', amount_minor: 1500, applied: true }],
			error: null
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_record_adjustment',
			expect.objectContaining({
				p_organization_id: organizationId,
				p_idempotency_key: idempotencyKey,
				p_actor: PLATFORM_OWNER_ACTOR_ID
			})
		);
		expect(client.auditInsert).toHaveBeenCalledTimes(1);
	});

	it('never audits a replayed adjustment (same idempotency key)', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = adjustmentClient({
			data: [{ id: 'entry-1', entry_kind: 'adjustment', amount_minor: 1500, applied: false }],
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
		const client = adjustmentClient({
			data: null,
			error: {
				code: 'P0001',
				message: 'adjustment would drive the settled balance below the reserved funds'
			}
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(409);
	});
});
