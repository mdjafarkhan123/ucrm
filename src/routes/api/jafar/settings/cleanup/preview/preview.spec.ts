import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function getEvent(organizationIdParam?: string) {
	const url = new URL('http://localhost/api/jafar/settings/cleanup/preview');
	if (organizationIdParam !== undefined)
		url.searchParams.set('organization_id', organizationIdParam);
	return { url } as Parameters<typeof GET>[0];
}

describe('platform owner cleanup impact preview GET boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue(session());
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await GET(getEvent(organizationId));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects a request missing a valid organization id', async () => {
		const response = await GET(getEvent('not-a-uuid'));

		expect(response.status).toBe(400);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('reads the impact from the shared preview RPC', async () => {
		const impact = { active_reply_aliases: 2, queued_messages: 5, recent_replies: 1 };
		const rpc = vi.fn().mockResolvedValue({ data: impact, error: null });
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await GET(getEvent(organizationId));
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('preview_organization_closure_impact', {
			target_organization_id: organizationId
		});
		expect(body).toEqual({ impact });
	});

	it('returns a 500 when the preview RPC fails', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { message: 'boom' } });
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await GET(getEvent(organizationId));

		expect(response.status).toBe(500);
	});
});
