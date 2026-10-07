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
			`http://localhost/api/jafar/organizations/${org}/communications/sms/registrations/${reg}/checks`,
			{
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			}
		),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function checkClient(
	existing: { organization_id: string; status: string } | null = {
		organization_id: organizationId,
		status: 'approved'
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

describe('platform owner SMS registration check boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(postEvent({}));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns not found when the registration belongs to another organization', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = checkClient({ organization_id: 'other-org', status: 'approved' });
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({}));

		expect(response.status).toBe(404);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('records a readiness check with no detail required, using the platform-owner sentinel actor', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = checkClient();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({}));

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_record_registration_check',
			expect.objectContaining({
				p_registration_id: registrationId,
				p_checked_by: PLATFORM_OWNER_ACTOR_ID,
				p_detail: undefined
			})
		);
		expect(client.auditInsert).toHaveBeenCalledTimes(1);
	});

	it('passes an optional detail note through to the command', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = checkClient();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent({ detail: 'confirmed live with the provider console' }));

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_record_registration_check',
			expect.objectContaining({ p_detail: 'confirmed live with the provider console' })
		);
	});
});
