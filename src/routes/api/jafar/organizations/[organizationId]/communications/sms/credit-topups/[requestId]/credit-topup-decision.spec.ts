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
const requestId = '223e4567-e89b-12d3-a456-426614174000';

function session() {
	return {
		email: 'owner@example.com',
		sessionId: 'session-id',
		role: null,
		memberId: null,
		name: null
	};
}

function postEvent(body: unknown, ids: { org?: string; req?: string } = {}) {
	const org = ids.org ?? organizationId;
	const req = ids.req ?? requestId;
	return {
		params: { organizationId: org, requestId: req },
		request: new Request(
			`http://localhost/api/jafar/organizations/${org}/communications/sms/credit-topups/${req}`,
			{
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			}
		),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function topupClient(
	existing: { organization_id: string; status: string } | null = {
		organization_id: organizationId,
		status: 'awaiting_confirmation'
	},
	rpcResult: { data: unknown; error: { code: string; message: string } | null } = {
		data: { id: requestId, status: 'confirmed' },
		error: null
	}
) {
	const auditInsert = vi.fn().mockResolvedValue({ error: null });
	const client = {
		from: (table: string) => {
			if (table === 'communication_sms_credit_topup_requests') {
				const result = {
					data: existing ? { id: requestId, ...existing } : null,
					error: null
				};
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
	return client;
}

describe('platform owner SMS credit top-up decision boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(postEvent({ action: 'reject', decision_reason: 'duplicate wire' }));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the decision before database access', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await POST(postEvent({ action: 'confirm', settled_amount_minor: -100 }));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires password reconfirmation for a money decision', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(postEvent({ action: 'confirm', settled_amount_minor: 5000 }));

		expect(response.status).toBe(403);
		expect((await response.json()).step_up_required).toBe(true);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns not found when the request belongs to another organization', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = topupClient({ organization_id: 'other-org', status: 'awaiting_confirmation' });
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ action: 'confirm', settled_amount_minor: 5000 }));

		expect(response.status).toBe(404);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('confirms a top-up with the platform-owner sentinel actor and records an audit entry', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = topupClient();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			postEvent({ action: 'confirm', settled_amount_minor: 5000, decision_reason: 'wire received' })
		);

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_confirm_credit_topup',
			expect.objectContaining({
				p_request_id: requestId,
				p_decided_by: PLATFORM_OWNER_ACTOR_ID,
				p_settled_amount_minor: 5000,
				p_decision_reason: 'wire received'
			})
		);
		expect(client.auditInsert).toHaveBeenCalledTimes(1);
	});

	it('rejects a top-up through the reject command', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = topupClient(
			{ organization_id: organizationId, status: 'awaiting_confirmation' },
			{ data: { id: requestId, status: 'rejected' }, error: null }
		);
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			postEvent({ action: 'reject', decision_reason: 'no payment arrived' })
		);

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_reject_credit_topup',
			expect.objectContaining({
				p_request_id: requestId,
				p_decided_by: PLATFORM_OWNER_ACTOR_ID,
				p_decision_reason: 'no payment arrived'
			})
		);
	});

	it('translates a database rule violation into a conflict', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = topupClient(
			{ organization_id: organizationId, status: 'awaiting_confirmation' },
			{
				data: null,
				error: {
					code: 'P0001',
					message: 'top-up request is confirmed and can no longer be confirmed'
				}
			}
		);
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ action: 'confirm', settled_amount_minor: 5000 }));

		expect(response.status).toBe(409);
		expect((await response.json()).error).toContain('can no longer be confirmed');
	});
});
