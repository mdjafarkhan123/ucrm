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
			`http://localhost/api/jafar/organizations/${org}/communications/sms/refunds`,
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

function entryListClient(entries: Record<string, unknown>[]) {
	return {
		from: (table: string) => {
			if (table === 'communication_sms_credit_ledger_entries') {
				const builder = {
					select: () => builder,
					eq: () => builder,
					order: () => Promise.resolve({ data: entries, error: null })
				};
				return builder;
			}
			throw new Error(`Unexpected table: ${table}`);
		}
	};
}

function refundClient(rpcResult: {
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
	return { amount_minor: 1000, reason: 'partial refund', idempotency_key: idempotencyKey };
}

describe('platform owner SMS refund read', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await GET(getEvent());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('lists this organization refund entries only', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = entryListClient([
			{ id: 'entry-1', amount_minor: -1000 },
			{ id: 'entry-2', amount_minor: -250 }
		]);
		mockedClient.mockReturnValue(client as never);

		const response = await GET(getEvent());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.entries).toHaveLength(2);
		expect(body.entries[0]).toMatchObject({ id: 'entry-1', amount_minor: -1000 });
	});
});

describe('platform owner SMS refund boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects a negative amount before database access', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await POST(postEvent({ ...validBody(), amount_minor: -100 }));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires password reconfirmation before recording a refund', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(403);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('records a refund with the platform-owner sentinel actor and audits a genuinely new post', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = refundClient({
			data: [{ id: 'entry-1', entry_kind: 'refund', amount_minor: -1000, applied: true }],
			error: null
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_record_refund',
			expect.objectContaining({
				p_organization_id: organizationId,
				p_amount_minor: 1000,
				p_idempotency_key: idempotencyKey,
				p_actor: PLATFORM_OWNER_ACTOR_ID
			})
		);
		expect(client.auditInsert).toHaveBeenCalledTimes(1);
	});

	it('never audits a replayed refund (same idempotency key)', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = refundClient({
			data: [{ id: 'entry-1', entry_kind: 'refund', amount_minor: -1000, applied: false }],
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
		const client = refundClient({
			data: null,
			error: { code: 'P0001', message: 'refund exceeds the unreserved settled balance' }
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(409);
	});
});
