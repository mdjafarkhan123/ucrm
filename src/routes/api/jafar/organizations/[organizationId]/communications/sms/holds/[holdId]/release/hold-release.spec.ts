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
const holdId = '223e4567-e89b-12d3-a456-426614174000';

function session() {
	return {
		email: 'owner@example.com',
		sessionId: 'session-id',
		role: null,
		access: null,
		memberId: null,
		name: null
	};
}

function postEvent(body: unknown, ids: { org?: string; hold?: string } = {}) {
	const org = ids.org ?? organizationId;
	const hold = ids.hold ?? holdId;
	return {
		params: { organizationId: org, holdId: hold },
		request: new Request(
			`http://localhost/api/jafar/organizations/${org}/communications/sms/holds/${hold}/release`,
			{
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			}
		),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function releaseClient(
	existing: { organization_id: string; status: string } | null = {
		organization_id: organizationId,
		status: 'active'
	},
	rpcResult: { data: unknown; error: { code: string; message: string } | null } = {
		data: { id: holdId, status: 'released' },
		error: null
	}
) {
	const auditInsert = vi.fn().mockResolvedValue({ error: null });
	return {
		from: (table: string) => {
			if (table === 'communication_sms_holds') {
				const result = { data: existing ? { id: holdId, ...existing } : null, error: null };
				const builder = {
					select: () => builder,
					eq: () => builder,
					maybeSingle: () => Promise.resolve(result)
				};
				return builder;
			}
			if (table === 'access_audit_events') return { insert: auditInsert };
			throw new Error(`Unexpected table: ${table}`);
		},
		rpc: vi.fn().mockResolvedValue(rpcResult),
		auditInsert
	};
}

describe('platform owner SMS hold release boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(postEvent({ release_reason: 'review complete' }));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires password reconfirmation before releasing a hold', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(postEvent({ release_reason: 'review complete' }));

		expect(response.status).toBe(403);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns not found when the hold belongs to another organization', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = releaseClient({ organization_id: 'other-org', status: 'active' });
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ release_reason: 'review complete' }));

		expect(response.status).toBe(404);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('releases a hold with the platform-owner sentinel actor and records an audit entry', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = releaseClient();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ release_reason: 'review complete' }));

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_release_hold',
			expect.objectContaining({
				p_hold_id: holdId,
				p_released_by: PLATFORM_OWNER_ACTOR_ID,
				p_release_reason: 'review complete'
			})
		);
		expect(client.auditInsert).toHaveBeenCalledTimes(1);
	});

	it('translates an already-released rule violation into a conflict', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = releaseClient(undefined, {
			data: null,
			error: { code: 'P0001', message: 'hold is not active and cannot be released' }
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ release_reason: 'review complete' }));

		expect(response.status).toBe(409);
	});
});
