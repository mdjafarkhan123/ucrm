import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { OrganizationAccessNotFoundError } from '$lib/server/access/effective';
import { loadAccessComparison } from '$lib/server/experience/access-comparison';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/access/effective', () => ({
	OrganizationAccessNotFoundError: class OrganizationAccessNotFoundError extends Error {}
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/experience/access-comparison', () => ({ loadAccessComparison: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedLoad = vi.mocked(loadAccessComparison);
const ownerSession = {
	email: 'owner@example.com',
	sessionId: 'session-id',
	role: null,
	access: null,
	memberId: null,
	name: null
};

function event(organizationId: string) {
	return { params: { organizationId } } as Parameters<typeof GET>[0];
}

describe('access comparison API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		expect((await GET(event('0eb69057-740d-4bd3-ba3f-5d1646f26155'))).status).toBe(401);
		expect(mockedLoad).not.toHaveBeenCalled();
	});

	it('validates the organization identifier after owner authentication', async () => {
		mockedOwnerSession.mockResolvedValue(ownerSession);
		expect((await GET(event('not-a-uuid'))).status).toBe(422);
	});

	it('answers an unknown organization with 404 and never caches the comparison', async () => {
		mockedOwnerSession.mockResolvedValue(ownerSession);
		mockedLoad.mockRejectedValueOnce(new OrganizationAccessNotFoundError());
		expect((await GET(event('0eb69057-740d-4bd3-ba3f-5d1646f26155'))).status).toBe(404);

		mockedLoad.mockResolvedValueOnce({ verdict: 'same' } as never);
		const response = await GET(event('0eb69057-740d-4bd3-ba3f-5d1646f26155'));
		expect(response.status).toBe(200);
		expect(response.headers.get('cache-control')).toBe('no-store');
	});
});
