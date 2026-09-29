import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const originalEventId = '223e4567-e89b-12d3-a456-426614174000';

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function getEvent(id = organizationId) {
	return { params: { organizationId: id } } as Parameters<typeof GET>[0];
}

function query(data: unknown) {
	const result = { data, error: null };
	const builder = {
		select: () => builder,
		eq: () => builder,
		in: () => builder,
		order: () => builder,
		maybeSingle: () => Promise.resolve(result),
		then: (resolve: (value: typeof result) => unknown) => Promise.resolve(result).then(resolve)
	};
	return builder;
}

function commercialClient(lifecycleStatus: 'active' | 'suspended' = 'active') {
	return {
		from: (table: string) => {
			if (table === 'organizations')
				return query({
					id: organizationId,
					name: 'Ridgeway Electric',
					lifecycle_status: lifecycleStatus
				});
			if (table === 'organization_commercial_state')
				return query({
					paid_through_date: '2026-08-31',
					paid_through_source: 'renewal',
					grace_ends_at: '2026-09-08T03:59:59.999Z',
					grace_basis_timezone: 'America/New_York',
					last_event_id: originalEventId,
					state_version: 2,
					updated_at: '2026-08-13T00:00:00Z'
				});
			if (table === 'organization_commercial_settings')
				return query({ commercial_timezone: 'America/New_York', timezone_source: 'imported' });
			if (table === 'organization_closure_records') return query(null);
			throw new Error(`Unexpected table: ${table}`);
		}
	};
}

describe('platform owner commercial API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await GET(getEvent());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('includes the open closure record when the organization is pending closure', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = commercialClient('active');
		const closingRecord = {
			id: 'closure-1',
			reason: 'Contractor requested closure',
			started_at: '2026-08-01T00:00:00Z',
			deadline_at: '2026-08-31T00:00:00Z'
		};
		const baseFrom = client.from;
		client.from = ((table: string) =>
			table === 'organization_closure_records' ? query(closingRecord) : baseFrom(table)) as never;
		mockedClient.mockReturnValue(client as never);

		const response = await GET(getEvent());
		const result = await response.json();

		expect(response.status).toBe(200);
		expect(result.closure).toEqual(closingRecord);
	});
});
