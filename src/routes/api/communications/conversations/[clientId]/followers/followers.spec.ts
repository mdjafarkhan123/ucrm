import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST, DELETE } from './+server';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/auth/organization', () => ({ getOrganizationContext: vi.fn() }));
vi.mock('$lib/server/access/effective', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/effective')>(
		'$lib/server/access/effective'
	);
	return { ...actual, resolveOrganizationAccess: vi.fn() };
});
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});

const mockedAuth = vi.mocked(getOrganizationContext);
const mockedAccess = vi.mocked(resolveOrganizationAccess);
const mockedOwnerClient = vi.mocked(getOwnerSupabaseClient);
const mockedRateLimit = vi.mocked(checkRateLimit);
const clientId = '00000000-0000-4000-8000-000000000001';

function event() {
	return {
		params: { clientId },
		locals: { supabase: {} }
	} as Parameters<typeof POST>[0];
}

describe('following/unfollowing a conversation', () => {
	const upsert = vi.fn();
	const del = vi.fn();
	const from = vi.fn(() => ({
		upsert,
		delete: () => ({ eq: () => ({ eq: () => ({ eq: del }) }) })
	}));

	beforeEach(() => {
		vi.clearAllMocks();
		mockedAuth.mockResolvedValue({
			organization: { id: 'org-1' },
			user: { id: 'user-1' }
		} as never);
		mockedOwnerClient.mockReturnValue({ from } as never);
		mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		upsert.mockResolvedValue({ error: null });
		del.mockResolvedValue({ error: null });
	});

	it('denies a member with neither conversations permission', async () => {
		mockedAccess.mockResolvedValue({ permissions: {}, features: {} } as never);
		const response = await POST(event());
		expect(response.status).toBe(403);
		expect(upsert).not.toHaveBeenCalled();
	});

	it('lets an assigned-only viewer follow for themselves -- no manage_assignment needed', async () => {
		mockedAccess.mockResolvedValue({
			permissions: { 'conversations.view_assigned': true },
			features: {}
		} as never);
		const response = await POST(event());
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ following: true });
		expect(upsert).toHaveBeenCalledWith(
			{ organization_id: 'org-1', client_id: clientId, user_id: 'user-1' },
			{ onConflict: 'organization_id,client_id,user_id', ignoreDuplicates: true }
		);
	});

	it("unfollows, always scoped to the caller's own user_id", async () => {
		mockedAccess.mockResolvedValue({
			permissions: { 'conversations.view_team': true },
			features: {}
		} as never);
		const response = await DELETE(event());
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ following: false });
		expect(del).toHaveBeenCalledWith('user_id', 'user-1');
	});
});
