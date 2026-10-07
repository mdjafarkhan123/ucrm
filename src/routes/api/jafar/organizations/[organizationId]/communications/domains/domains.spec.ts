import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';

function event(id = organizationId) {
	const url = `http://localhost/api/jafar/organizations/${id}/communications/domains`;
	return {
		params: { organizationId: id },
		request: new Request(url),
		url: new URL(url),
		cookies: {}
	} as Parameters<typeof GET>[0];
}

describe('owner everyday email domain list', () => {
	beforeEach(() => vi.clearAllMocks());

	it('does not expose sending domains without the separate owner session', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);
		const response = await GET(event());
		expect(response.status).toBe(401);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('rejects an invalid organization identifier before database access', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-1',
			role: null,
			access: null,
			memberId: null,
			name: null
		});
		const response = await GET(event('not-a-uuid'));
		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});
});
