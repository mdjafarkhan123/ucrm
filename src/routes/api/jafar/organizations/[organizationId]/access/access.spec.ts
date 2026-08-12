import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';

vi.mock('$lib/server/auth/owner', () => ({
	getOwnerSession: vi.fn()
}));
vi.mock('$lib/server/access/effective', () => ({
	OrganizationAccessNotFoundError: class OrganizationAccessNotFoundError extends Error {},
	resolveOrganizationAccess: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({
	getOwnerSupabaseClient: vi.fn()
}));

const mockedOwnerSession = vi.mocked(getOwnerSession);

function event(organizationId: string) {
	return {
		params: { organizationId },
		url: new URL('http://localhost/api/jafar/organizations/' + organizationId + '/access'),
		cookies: {}
	} as Parameters<typeof GET>[0];
}

describe('platform owner access API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);

		const response = await GET(event('00000000-0000-0000-0000-000000000001'));

		expect(response.status).toBe(401);
	});

	it('validates organization identifiers after owner authentication', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});

		const response = await GET(event('not-a-uuid'));

		expect(response.status).toBe(422);
	});
});
