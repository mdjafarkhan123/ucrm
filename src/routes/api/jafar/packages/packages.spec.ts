import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

function query(data: unknown, error: null | { message: string } = null) {
	const builder = {
		select: () => builder,
		order: () => builder,
		then: (resolve: (value: { data: unknown; error: null | { message: string } }) => unknown) =>
			Promise.resolve({ data, error }).then(resolve)
	};
	return builder;
}

function event() {
	return { url: new URL('http://localhost/api/jafar/packages'), cookies: {} } as Parameters<
		typeof GET
	>[0];
}

describe('platform owner package read API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);

		const response = await GET(event());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns package versions with controlled feature and limit assignments', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedClient.mockReturnValue({
			from: (table: string) =>
				({
					platform_packages: query([
						{ package_id: 'package-growth', package_key: 'growth', sort_order: 2 }
					]),
					platform_package_versions: query([
						{ id: 'version-growth-1', package_id: 'package-growth', version_number: 1 }
					]),
					features: query([{ feature_key: 'core.team', description: 'Team' }]),
					platform_package_version_features: query([
						{ package_version_id: 'version-growth-1', feature_key: 'core.team' }
					]),
					platform_package_version_limits: query([
						{
							package_version_id: 'version-growth-1',
							limit_key: 'employee_seats',
							limit_state: 'numeric',
							limit_value: 10
						}
					])
				})[table] ?? query([])
		} as never);

		const response = await GET(event());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.packages[0].versions[0].features).toEqual(['core.team']);
		expect(body.packages[0].versions[0].limits).toEqual([
			{ limit_key: 'employee_seats', limit_state: 'numeric', limit_value: 10 }
		]);
		expect(body.limit_catalog).toEqual([{ limit_key: 'employee_seats', label: 'Employee seats' }]);
	});

	it('returns a server error when a package query fails', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedClient.mockReturnValue({
			from: () => query([], { message: 'database unavailable' })
		} as never);

		const response = await GET(event());

		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'Package definitions could not be loaded.' });
	});

	it('returns service unavailable when the owner package service throws', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedClient.mockImplementation(() => {
			throw new Error('service unavailable');
		});

		const response = await GET(event());

		expect(response.status).toBe(503);
		expect(await response.json()).toEqual({ error: 'Package definitions could not be loaded.' });
	});
});
