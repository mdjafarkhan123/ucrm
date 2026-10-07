import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';

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

function getEvent(org = organizationId) {
	return { params: { organizationId: org }, cookies: {} } as Parameters<typeof GET>[0];
}

function listClient(senders: Record<string, unknown>[]) {
	const builder = {
		select: () => builder,
		eq: () => builder,
		order: () => Promise.resolve({ data: senders, error: null })
	};
	return {
		from: (table: string) => {
			if (table === 'communication_sms_sender_identities') return builder;
			throw new Error(`Unexpected table: ${table}`);
		}
	};
}

describe('platform owner SMS sender identity list', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await GET(getEvent());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('lists the organization sender identities', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = listClient([
			{
				id: 'sender-1',
				phone_number: '+15551234567',
				display_name: 'Support line',
				lifecycle_state: 'ready',
				allows_manual: true,
				allows_automated: true,
				capable_sms: true,
				capable_mms: false,
				capable_voice: false,
				registration_id: null
			}
		]);
		mockedClient.mockReturnValue(client as never);

		const response = await GET(getEvent());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.senders).toEqual([expect.objectContaining({ id: 'sender-1', capable_sms: true })]);
	});
});
