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
		mockedOwnerSession.mockResolvedValue(null);

		const response = await GET(event());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects an invalid organization identifier', async () => {
		mockedOwnerSession.mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		});

		const response = await GET(event('not-a-uuid'));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the organization does not exist', async () => {
		mockedOwnerSession.mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
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

	function mockTeamClient(options: {
		overrides?: Array<{ user_id: string; permission_key: string; override_state: string }>;
		getUserById?: (userId: string) => Promise<{ data: { user: { email: string } | null }; error: unknown }>;
	}) {
		return {
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
				if (table === 'organization_member_permission_overrides') {
					return {
						select: () => ({
							eq: async () => ({ data: options.overrides ?? [], error: null })
						})
					};
				}
				throw new Error(`unexpected table ${table}`);
			},
			auth: {
				admin: {
					getUserById:
						options.getUserById ??
						(async (userId: string) => ({
							data: { user: { email: `${userId}@example.com` } },
							error: null
						}))
				}
			}
		} as never;
	}

	it('returns members joined with profile name and auth email, and flags administrator readiness', async () => {
		mockedOwnerSession.mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		});
		mockedClient.mockReturnValue(mockTeamClient({}));

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
				email: 'user-1@example.com',
				permission_overrides: []
			},
			{
				user_id: 'user-2',
				role: 'field',
				created_at: '2026-02-01T00:00:00Z',
				full_name: 'Fin Tech',
				email: 'user-2@example.com',
				permission_overrides: []
			}
		]);
	});

	it('groups permission overrides per member', async () => {
		mockedOwnerSession.mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		});
		mockedClient.mockReturnValue(
			mockTeamClient({
				overrides: [
					{ user_id: 'user-2', permission_key: 'invoices.manage', override_state: 'grant' }
				]
			})
		);

		const response = await GET(event());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.members[0].permission_overrides).toEqual([]);
		expect(body.members[1].permission_overrides).toEqual([
			{ permission_key: 'invoices.manage', override_state: 'grant' }
		]);
	});

	it('degrades a single member to a null email instead of failing the whole list', async () => {
		mockedOwnerSession.mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		});
		mockedClient.mockReturnValue(
			mockTeamClient({
				getUserById: async (userId: string) => {
					if (userId === 'user-1') throw new Error('Auth admin API unavailable.');
					return { data: { user: { email: `${userId}@example.com` } }, error: null };
				}
			})
		);

		const response = await GET(event());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.members[0].email).toBeNull();
		expect(body.members[1].email).toBe('user-2@example.com');
	});
});
