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
	return { url: new URL('http://localhost/api/jafar/message-templates'), params: {}, cookies: {} } as Parameters<
		typeof GET
	>[0];
}

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

describe('platform owner message template list API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const response = await GET(event());
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns every template with its placeholder catalog attached', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue({
			from: () =>
				query([
					{
						template_key: 'password_setup',
						published_version: 1,
						published_at: '2026-08-12T00:00:00Z',
						published_by_owner_email: 'system',
						updated_at: '2026-08-12T00:00:00Z'
					}
				])
		} as never);

		const response = await GET(event());
		expect(response.status).toBe(200);
		const body = await response.json();
		expect(body.templates[0].template_key).toBe('password_setup');
		expect(body.templates[0].placeholders).toEqual(
			expect.arrayContaining([expect.objectContaining({ key: 'setup_link', required: true })])
		);
	});

	it('returns a safe server error when the query fails', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue({
			from: () => query(null, { message: 'internal database details' })
		} as never);

		const response = await GET(event());
		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'Message templates could not be loaded.' });
	});
});
