import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const registrationId = '223e4567-e89b-12d3-a456-426614174000';

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

function postEvent(body: unknown, ids: { org?: string; reg?: string } = {}) {
	const org = ids.org ?? organizationId;
	const reg = ids.reg ?? registrationId;
	return {
		params: { organizationId: org, registrationId: reg },
		request: new Request(
			`http://localhost/api/jafar/organizations/${org}/communications/sms/registrations/${reg}/outcome`,
			{
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			}
		),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function outcomeClient(
	existing: { organization_id: string; status: string } | null = {
		organization_id: organizationId,
		status: 'under_review'
	},
	rpcResult: { data: unknown; error: { code: string; message: string } | null } = {
		data: { id: registrationId, status: 'approved' },
		error: null
	}
) {
	const auditInsert = vi.fn().mockResolvedValue({ error: null });
	return {
		from: (table: string) => {
			if (table === 'communication_sms_registrations') {
				const result = { data: existing ? { id: registrationId, ...existing } : null, error: null };
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

describe('platform owner SMS registration outcome boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(
			postEvent({ status: 'approved', provider_outcome: 'brand verified' })
		);

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires the required fixes for an action_needed outcome', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await POST(postEvent({ status: 'action_needed' }));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns not found when the registration belongs to another organization', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = outcomeClient({ organization_id: 'other-org', status: 'under_review' });
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			postEvent({ status: 'approved', provider_outcome: 'brand verified' })
		);

		expect(response.status).toBe(404);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('records an approved outcome with the platform-owner sentinel actor and audits it', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = outcomeClient();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			postEvent({ status: 'approved', provider_outcome: 'brand verified' })
		);

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_record_registration_outcome',
			expect.objectContaining({
				p_registration_id: registrationId,
				p_status: 'approved',
				p_decided_by: PLATFORM_OWNER_ACTOR_ID,
				p_provider_outcome: 'brand verified'
			})
		);
		expect(client.auditInsert).toHaveBeenCalledTimes(1);
	});

	it('records an action_needed outcome through the required fixes field', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = outcomeClient(
			{ organization_id: organizationId, status: 'under_review' },
			{ data: { id: registrationId, status: 'action_needed' }, error: null }
		);
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			postEvent({ status: 'action_needed', required_fixes: 'legal business name mismatch' })
		);

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_record_registration_outcome',
			expect.objectContaining({
				p_status: 'action_needed',
				p_required_fixes: 'legal business name mismatch'
			})
		);
	});

	it('translates a database rule violation into a conflict', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = outcomeClient(
			{ organization_id: organizationId, status: 'waiting_for_info' },
			{
				data: null,
				error: { code: 'P0001', message: 'registration has no pending review to decide' }
			}
		);
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			postEvent({ status: 'approved', provider_outcome: 'brand verified' })
		);

		expect(response.status).toBe(409);
		expect((await response.json()).error).toContain('no pending review');
	});
});
