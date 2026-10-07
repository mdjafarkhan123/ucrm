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

function listClient(events: Record<string, unknown>[], registrations: Record<string, unknown>[]) {
	const eventsBuilder = {
		select: () => eventsBuilder,
		eq: () => eventsBuilder,
		order: () => eventsBuilder,
		limit: () => Promise.resolve({ data: events, error: null })
	};
	const registrationsBuilder = {
		select: () => registrationsBuilder,
		eq: () => Promise.resolve({ data: registrations, error: null })
	};
	return {
		from: (table: string) => {
			if (table === 'communication_sms_registration_events') return eventsBuilder;
			if (table === 'communication_sms_registrations') return registrationsBuilder;
			throw new Error(`Unexpected table: ${table}`);
		}
	};
}

describe('platform owner SMS registration/audit history list', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await GET(getEvent());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects an invalid organization id', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await GET(getEvent('not-a-uuid'));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('lists events joined with their registration key', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = listClient(
			[
				{
					id: 'event-1',
					registration_id: 'registration-1',
					event_type: 'approved',
					from_status: 'under_review',
					to_status: 'approved',
					detail: null,
					provider_outcome: 'Verified business identity',
					created_at: '2026-09-14T00:00:00.000Z'
				}
			],
			[{ id: 'registration-1', country_code: 'US', sender_type: 'long_code', use_case: 'mixed' }]
		);
		mockedClient.mockReturnValue(client as never);

		const response = await GET(getEvent());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.events).toEqual([
			expect.objectContaining({
				id: 'event-1',
				event_type: 'approved',
				country_code: 'US',
				sender_type: 'long_code',
				use_case: 'mixed'
			})
		]);
	});

	it('leaves the registration key null when the registration is missing', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = listClient(
			[
				{
					id: 'event-1',
					registration_id: 'unknown-registration',
					event_type: 'started',
					from_status: null,
					to_status: 'waiting_for_info',
					detail: null,
					provider_outcome: null,
					created_at: '2026-09-14T00:00:00.000Z'
				}
			],
			[]
		);
		mockedClient.mockReturnValue(client as never);

		const response = await GET(getEvent());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.events[0]).toEqual(
			expect.objectContaining({ country_code: null, sender_type: null, use_case: null })
		);
	});
});
