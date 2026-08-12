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

describe('platform owner team API boundary', () => {
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

	it('returns members joined with profile name and auth email, and flags administrator readiness', async () => {
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
				if (table === 'organization_members') {
					return {
						select: () => ({
							eq: () => ({
								order: async () => ({
									data: [
										{ user_id: 'user-1', role: 'owner', created_at: '2026-01-01T00:00:00Z' },
										{ user_id: 'user-2', role: 'field', created_at: '2026-02-01T00:00:00Z' }
									],
									error: null
								})
							})
						})
					};
				}
				if (table === 'profiles') {
					return {
						select: () => ({
							in: async () => ({
								data: [
									{ id: 'user-1', full_name: 'Rae Owner' },
									{ id: 'user-2', full_name: 'Fin Tech' }
								],
								error: null
							})
						})
					};
				}
				throw new Error(`unexpected table ${table}`);
			},
			auth: {
				admin: {
					getUserById: async (userId: string) => ({
						data: { user: { email: `${userId}@example.com` } },
						error: null
					})
				}
			}
		} as never);

		const response = await GET(event());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.has_administrator).toBe(true);
		expect(body.members).toEqual([
			{
				user_id: 'user-1',
				role: 'owner',
				created_at: '2026-01-01T00:00:00Z',
				full_name: 'Rae Owner',
				email: 'user-1@example.com'
			},
			{
				user_id: 'user-2',
				role: 'field',
				created_at: '2026-02-01T00:00:00Z',
				full_name: 'Fin Tech',
				email: 'user-2@example.com'
			}
		]);
	});
});
