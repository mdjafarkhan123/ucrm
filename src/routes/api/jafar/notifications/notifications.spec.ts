import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const calls: { method: string; args: unknown[] }[] = [];

/**
 * The route fires the list and the unread count together, so the fake distinguishes them by
 * whether the select asked for a head count -- the same way PostgREST itself does.
 */
function clientWith(options: {
	rows?: unknown[];
	count?: number;
	listError?: { message: string } | null;
	countError?: { message: string } | null;
}) {
	function builder(isCount: boolean) {
		const self = {
			select: (...args: unknown[]) => {
				calls.push({ method: 'select', args });
				return isCount ? countResult() : self;
			},
			order: (...args: unknown[]) => {
				calls.push({ method: 'order', args });
				return self;
			},
			limit: (...args: unknown[]) => {
				calls.push({ method: 'limit', args });
				return self;
			},
			is: (...args: unknown[]) => {
				calls.push({ method: 'is', args });
				return self;
			},
			or: (...args: unknown[]) => {
				calls.push({ method: 'or', args });
				return self;
			},
			then: (resolve: (value: unknown) => unknown) =>
				Promise.resolve({
					data: options.rows ?? [],
					error: options.listError ?? null
				}).then(resolve)
		};
		return self;
	}

	function countResult() {
		return {
			is: (...args: unknown[]) => {
				calls.push({ method: 'countIs', args });
				return Promise.resolve({
					count: options.count ?? 0,
					error: options.countError ?? null
				});
			}
		};
	}

	return {
		from: () => ({
			select: (...args: unknown[]) => {
				const isCount = args.length > 1;
				return builder(isCount).select(...args);
			}
		})
	};
}

function event(url = 'http://localhost/api/jafar/notifications') {
	return { url: new URL(url), params: {}, cookies: {} } as Parameters<typeof GET>[0];
}

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

describe('platform owner notifications list API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		calls.length = 0;
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);
		const response = await GET(event());
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects an unknown status filter', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const response = await GET(event('http://localhost/api/jafar/notifications?status=bogus'));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects a limit above the allowed page size', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const response = await GET(event('http://localhost/api/jafar/notifications?limit=5000'));
		expect(response.status).toBe(422);
	});

	it('returns unread notifications and the true unread total by default', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({ rows: [{ id: 'note-1', read_at: null }], count: 7 }) as never
		);

		const response = await GET(event());
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			notifications: [{ id: 'note-1', read_at: null }],
			unread_count: 7
		});
		expect(calls).toContainEqual({ method: 'is', args: ['read_at', null] });
	});

	it('drops the unread-only filter when the full history is requested', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(clientWith({ rows: [], count: 0 }) as never);

		const response = await GET(event('http://localhost/api/jafar/notifications?status=all'));
		expect(response.status).toBe(200);
		expect(calls.some((call) => call.method === 'is')).toBe(false);
	});

	it('searches the title and body of a notification', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(clientWith({ rows: [], count: 0 }) as never);

		await GET(event('http://localhost/api/jafar/notifications?status=all&search=Ridgeway'));
		expect(calls).toContainEqual({
			method: 'or',
			args: ['title.ilike.%Ridgeway%,body.ilike.%Ridgeway%']
		});
	});

	it('strips filter and wildcard characters so a search term cannot change the query', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(clientWith({ rows: [], count: 0 }) as never);

		await GET(
			event(
				`http://localhost/api/jafar/notifications?status=all&search=${encodeURIComponent('a,severity.eq.urgent)%_')}`
			)
		);
		const orCall = calls.find((call) => call.method === 'or');
		expect(orCall?.args[0]).not.toContain('severity.eq.urgent)');
		expect(orCall?.args[0]).not.toContain(',severity');
	});

	it('returns a safe server error when the query fails', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({ listError: { message: 'internal database details' } }) as never
		);

		const response = await GET(event());
		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'Notifications could not be loaded.' });
	});
});
