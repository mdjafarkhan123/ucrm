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

function session() {
	return {
		email: 'owner@example.com',
		sessionId: 'session-id',
		role: null,
		memberId: null,
		name: null
	};
}

function getEvent() {
	return { params: {}, cookies: {} } as Parameters<typeof GET>[0];
}

function holdListClient(holds: Record<string, unknown>[]) {
	return {
		from: (table: string) => {
			if (table === 'communication_sms_holds') {
				const builder = {
					select: () => builder,
					eq: () => builder,
					order: () => Promise.resolve({ data: holds, error: null })
				};
				return builder;
			}
			throw new Error(`Unexpected table: ${table}`);
		}
	};
}

function postEvent(body: unknown) {
	return {
		params: {},
		request: new Request('http://localhost/api/jafar/communications/sms/platform-holds', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function holdClient(rpcResult: { data: unknown; error: { code: string; message: string } | null }) {
	const auditInsert = vi.fn().mockResolvedValue({ error: null });
	return {
		from: (table: string) => {
			if (table === 'platform_audit_events') return { insert: auditInsert };
			throw new Error(`Unexpected table: ${table}`);
		},
		rpc: vi.fn().mockResolvedValue(rpcResult),
		auditInsert
	};
}

describe('platform owner platform-wide SMS hold read', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await GET(getEvent());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('lists platform-scoped holds only', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = holdListClient([{ id: 'hold-1', scope: 'platform', status: 'active' }]);
		mockedClient.mockReturnValue(client as never);

		const response = await GET(getEvent());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.holds).toHaveLength(1);
		expect(body.holds[0]).toMatchObject({ id: 'hold-1', status: 'active' });
	});
});

describe('platform owner platform-wide SMS hold placement boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(postEvent({ reason: 'global maintenance' }));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires password reconfirmation before pausing texting platform-wide', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(postEvent({ reason: 'global maintenance' }));

		expect(response.status).toBe(403);
		expect((await response.json()).step_up_required).toBe(true);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('places a platform hold with no organization and records a platform audit entry', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = holdClient({
			data: { id: 'hold-1', scope: 'platform', organization_id: null, status: 'active' },
			error: null
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ reason: 'global maintenance' }));

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_place_hold',
			expect.objectContaining({
				p_scope: 'platform',
				p_organization_id: null,
				p_reason: 'global maintenance',
				p_placed_by: PLATFORM_OWNER_ACTOR_ID
			})
		);
		expect(client.auditInsert).toHaveBeenCalledTimes(1);
	});

	it('translates a duplicate-active-hold rule violation into a conflict', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = holdClient({
			data: null,
			error: { code: 'P0001', message: 'an active platform hold already exists for this target' }
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ reason: 'global maintenance' }));

		expect(response.status).toBe(409);
		expect((await response.json()).error).toContain('already exists');
	});
});
