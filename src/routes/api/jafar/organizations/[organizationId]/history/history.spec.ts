import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';

function event(id = organizationId) {
	return { params: { organizationId: id } } as Parameters<typeof GET>[0];
}

describe('platform owner history API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);

		const response = await GET(event());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects an invalid organization identifier', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});

		const response = await GET(event('not-a-uuid'));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the organization does not exist', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedClient.mockReturnValue({
			from: () => ({
				select: () => ({
					eq: () => ({ maybeSingle: async () => ({ data: null, error: null }) })
				})
			})
		} as never);

		const response = await GET(event());

		expect(response.status).toBe(404);
	});

	it('merges audit, free-access, and commercial events into one feed sorted newest first', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedClient.mockReturnValue({
			from: (table: string) => {
				if (table === 'organizations') {
					return {
						select: () => ({
							eq: () => ({
								maybeSingle: async () => ({
									data: { id: organizationId, name: 'Ridgeway Electric' },
									error: null
								})
							})
						})
					};
				}
				if (table === 'access_audit_events') {
					return {
						select: () => ({
							eq: () => ({
								order: () => ({
									limit: async () => ({
						data: [
							{
												id: 'audit-1',
												event_type: 'organization.lifecycle_changed',
												target_type: 'organization.lifecycle_status',
												target_key: null,
												actor_owner_email: 'owner@example.com',
												before_state: { lifecycle_status: 'active' },
												after_state: { lifecycle_status: 'suspended' },
												created_at: '2026-08-10T00:00:00Z'
											}
										],
										error: null
									})
								})
							})
						})
					};
				}
				if (table === 'organization_free_access_events') {
					return {
						select: () => ({
							eq: () => ({
								order: () => ({
									limit: async () => ({
										data: [
											{
												id: 'free-1',
												action: 'grant',
												package_version_id: 'version-1',
												access_until_date: '2026-09-01',
												reason: 'Pilot',
												actor_owner_email: 'owner@example.com',
												occurred_at: '2026-08-11T00:00:00Z'
											}
										],
										error: null
									})
								})
							})
						})
					};
				}
				if (table === 'organization_commercial_events') {
					return {
						select: () => ({
							eq: () => ({
								order: () => ({
									limit: async () => ({
										data: [
											{
												id: 'commercial-2',
												event_kind: 'package_version_changed',
												summary: 'Package changed.',
												private_reason: 'Pilot upgrade',
												private_reference: null,
												amount_usd_cents: null,
												original_confirmation_id: null,
												paid_through_effect: 'unchanged',
												paid_through_before: '2026-08-31',
												paid_through_after: '2026-08-31',
												change_before: { package_version_id: 'version-1', version_number: 1 },
												change_after: { package_version_id: 'version-2', version_number: 2 },
												actor_owner_email: 'owner@example.com',
												occurred_at: '2026-08-12T12:00:00Z'
											},
											{
												id: 'commercial-1',
												event_kind: 'renewal_confirmed',
												summary: 'Renewal recorded.',
												private_reason: null,
												private_reference: 'bank-123',
												amount_usd_cents: 9900,
												original_confirmation_id: null,
												paid_through_effect: 'set',
												paid_through_before: '2026-08-31',
												paid_through_after: '2026-09-30',
												actor_owner_email: 'owner@example.com',
												occurred_at: '2026-08-12T00:00:00Z'
											}
										],
										error: null
									})
								})
							})
						})
					};
				}
				throw new Error(`unexpected table ${table}`);
			}
		} as never);

		const response = await GET(event());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.events).toEqual([
			{
				id: 'commercial:commercial-2',
				event_type: 'commercial.package_version_changed',
				target_type: 'organization.commercial_access',
				target_key: null,
				actor_email: 'owner@example.com',
				occurred_at: '2026-08-12T12:00:00Z',
				before_state: { package_version_id: 'version-1', version_number: 1 },
				after_state: {
					package_version_id: 'version-2',
					version_number: 2,
					summary: 'Package changed.',
					private_reason: 'Pilot upgrade',
					private_reference: null,
					amount_usd_cents: null,
					paid_through_effect: 'unchanged',
					paid_through_date: '2026-08-31'
				}
			},
			{
				id: 'commercial:commercial-1',
				event_type: 'commercial.renewal_confirmed',
				target_type: 'organization.commercial_access',
				target_key: null,
				actor_email: 'owner@example.com',
				occurred_at: '2026-08-12T00:00:00Z',
				before_state: { paid_through_date: '2026-08-31' },
				after_state: {
					summary: 'Renewal recorded.',
					private_reason: null,
					private_reference: 'bank-123',
					amount_usd_cents: 9900,
					paid_through_effect: 'set',
					paid_through_date: '2026-09-30'
				}
			},
			{
				id: 'free_access:free-1',
				event_type: 'free_access.grant',
				target_type: 'organization.free_access',
				target_key: 'version-1',
				actor_email: 'owner@example.com',
				occurred_at: '2026-08-11T00:00:00Z',
				before_state: null,
				after_state: { action: 'grant', access_until_date: '2026-09-01', reason: 'Pilot' }
			},
			{
				id: 'audit:audit-1',
				event_type: 'organization.lifecycle_changed',
				target_type: 'organization.lifecycle_status',
				target_key: null,
				actor_email: 'owner@example.com',
				occurred_at: '2026-08-10T00:00:00Z',
				before_state: { lifecycle_status: 'active' },
				after_state: { lifecycle_status: 'suspended' }
			}
		]);
	});
});
