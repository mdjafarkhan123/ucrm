import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { resolveOrganizationAccess } from '$lib/server/access/effective';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/access/effective', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/effective')>(
		'$lib/server/access/effective'
	);
	return { ...actual, resolveOrganizationAccess: vi.fn() };
});
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedResolveAccess = vi.mocked(resolveOrganizationAccess);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';

function event(id = organizationId) {
	return { params: { organizationId: id } } as Parameters<typeof GET>[0];
}

function query(data: unknown) {
	const result = { data, error: null };
	const builder = {
		select: () => builder,
		eq: () => builder,
		order: () => builder,
		limit: () => builder,
		maybeSingle: () =>
			Promise.resolve({ ...result, data: Array.isArray(data) ? (data[0] ?? null) : data }),
		then: (resolve: (value: typeof result) => unknown) => Promise.resolve(result).then(resolve)
	};
	return builder;
}

function freeAccessClient(agreement: unknown) {
	return {
		from: (table: string) => {
			if (table === 'organizations')
				return query({ id: organizationId, name: 'Ridgeway Electric' });
			if (table === 'organization_package_agreements') return query(agreement);
			if (table === 'organization_free_access_events') return query([]);
			throw new Error(`Unexpected table: ${table}`);
		}
	};
}

describe('platform owner free-access API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue({ email: 'owner@example.com', sessionId: 'session-id' });
		mockedResolveAccess.mockResolvedValue({ free_access: { active: null, future: null } } as never);
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await GET(event());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('reports whether the organization has a package agreement', async () => {
		mockedClient.mockReturnValue(freeAccessClient({ id: 'agreement-1' }) as never);

		const response = await GET(event());

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({
			has_package_assignment: true,
			free_access: { active: null, future: null },
			events: []
		});
	});

	it('switches free-access changes off while the package system is rebuilt', async () => {
		const response = await POST(event() as Parameters<typeof POST>[0]);

		expect(response.status).toBe(410);
		expect(mockedClient).not.toHaveBeenCalled();
	});
});
