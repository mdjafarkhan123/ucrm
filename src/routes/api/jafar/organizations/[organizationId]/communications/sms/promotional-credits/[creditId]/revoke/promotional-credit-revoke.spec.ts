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
const creditId = '223e4567-e89b-12d3-a456-426614174000';

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function postEvent(body: unknown, ids: { org?: string; credit?: string } = {}) {
	const org = ids.org ?? organizationId;
	const credit = ids.credit ?? creditId;
	return {
		params: { organizationId: org, creditId: credit },
		request: new Request(
			`http://localhost/api/jafar/organizations/${org}/communications/sms/promotional-credits/${credit}/revoke`,
			{
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			}
		),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function revokeClient(
	existing: { organization_id: string; status: string } | null = {
		organization_id: organizationId,
		status: 'active'
	},
	rpcResult: { data: unknown; error: { code: string; message: string } | null } = {
		data: { id: creditId, status: 'revoked' },
		error: null
	}
) {
	const auditInsert = vi.fn().mockResolvedValue({ error: null });
	return {
		from: (table: string) => {
			if (table === 'communication_sms_promotional_credits') {
				const result = { data: existing ? { id: creditId, ...existing } : null, error: null };
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

describe('platform owner SMS promotional-credit revoke boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(postEvent({ reason: 'granted in error' }));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns not found when the grant belongs to another organization', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = revokeClient({ organization_id: 'other-org', status: 'active' });
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ reason: 'granted in error' }));

		expect(response.status).toBe(404);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('revokes a grant with the platform-owner sentinel actor and records an audit entry', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = revokeClient();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ reason: 'granted in error' }));

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_revoke_promotional_credit',
			expect.objectContaining({
				p_credit_id: creditId,
				p_revoked_by: PLATFORM_OWNER_ACTOR_ID,
				p_reason: 'granted in error'
			})
		);
		expect(client.auditInsert).toHaveBeenCalledTimes(1);
	});

	it('translates an already-revoked rule violation into a conflict', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = revokeClient(undefined, {
			data: null,
			error: { code: 'P0001', message: 'promotional grant is not active and cannot be revoked' }
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ reason: 'granted in error' }));

		expect(response.status).toBe(409);
	});
});
