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

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function postEvent(body: unknown, org = organizationId) {
	return {
		params: { organizationId: org },
		request: new Request(
			`http://localhost/api/jafar/organizations/${org}/communications/sms/registrations`,
			{
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			}
		),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function registrationClient(rpcResult: {
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

describe('platform owner SMS registration start boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(
			postEvent({ country_code: 'us', sender_type: 'long_code', use_case: 'appointment reminders' })
		);

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the registration before database access', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await POST(
			postEvent({ country_code: 'usa', sender_type: 'long_code', use_case: 'reminders' })
		);

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('starts a registration with the platform-owner sentinel actor and records an audit entry', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = registrationClient({
			data: { id: 'reg-1', organization_id: organizationId, status: 'waiting_for_info' },
			error: null
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			postEvent({ country_code: 'us', sender_type: 'long_code', use_case: 'appointment reminders' })
		);

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_start_registration',
			expect.objectContaining({
				p_organization_id: organizationId,
				p_country_code: 'US',
				p_sender_type: 'long_code',
				p_use_case: 'appointment reminders',
				p_actor: PLATFORM_OWNER_ACTOR_ID
			})
		);
		expect(client.auditInsert).toHaveBeenCalledTimes(1);
	});

	it('translates a database rule violation into a conflict', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = registrationClient({
			data: null,
			error: { code: 'P0001', message: 'a registration cannot be reopened while approved' }
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			postEvent({ country_code: 'us', sender_type: 'long_code', use_case: 'appointment reminders' })
		);

		expect(response.status).toBe(409);
		expect((await response.json()).error).toContain('cannot be reopened');
	});
});
