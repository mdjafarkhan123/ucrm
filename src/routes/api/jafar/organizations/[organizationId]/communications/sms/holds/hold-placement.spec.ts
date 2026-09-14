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

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function postEvent(body: unknown, org = organizationId) {
	return {
		params: { organizationId: org },
		request: new Request(
			`http://localhost/api/jafar/organizations/${org}/communications/sms/holds`,
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

function holdClient(rpcResult: { data: unknown; error: { code: string; message: string } | null }) {
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

describe('platform owner SMS hold read', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await GET(getEvent());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('lists this organization holds only', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = holdListClient([
			{ id: 'hold-1', scope: 'organization', status: 'active' },
			{ id: 'hold-2', scope: 'provider', status: 'released' }
		]);
		mockedClient.mockReturnValue(client as never);

		const response = await GET(getEvent());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.holds).toHaveLength(2);
		expect(body.holds[0]).toMatchObject({ id: 'hold-1', status: 'active' });
	});
});

describe('platform owner SMS hold placement boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(postEvent({ scope: 'organization', reason: 'billing review' }));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects a platform-scope hold on this org-scoped route', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await POST(postEvent({ scope: 'platform', reason: 'billing review' }));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires password reconfirmation before placing a hold', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(postEvent({ scope: 'organization', reason: 'billing review' }));

		expect(response.status).toBe(403);
		expect((await response.json()).step_up_required).toBe(true);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('places a hold with the platform-owner sentinel actor and records an audit entry', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = holdClient({
			data: { id: 'hold-1', scope: 'organization', status: 'active' },
			error: null
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ scope: 'organization', reason: 'billing review' }));

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_place_hold',
			expect.objectContaining({
				p_scope: 'organization',
				p_organization_id: organizationId,
				p_reason: 'billing review',
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
			error: {
				code: 'P0001',
				message: 'an active organization hold already exists for this target'
			}
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ scope: 'organization', reason: 'billing review' }));

		expect(response.status).toBe(409);
		expect((await response.json()).error).toContain('already exists');
	});
});
