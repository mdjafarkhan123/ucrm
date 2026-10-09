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
 * whether the select asked for a head count -- the same way PostgREST itself does. Every step
 * is recorded; the count's steps are prefixed `count`.
 */
function clientWith(options: {
	rows?: unknown[];
	count?: number;
	listError?: { message: string } | null;
	countError?: { message: string } | null;
}) {
	function builder(isCount: boolean) {
		const record =
			(method: string) =>
			(...args: unknown[]) => {
				calls.push({ method: isCount ? `count${method[0].toUpperCase()}${method.slice(1)}` : method, args });
				return self;
			};
		const self = {
			order: record('order'),
			limit: record('limit'),
			is: record('is'),
			eq: record('eq'),
			or: record('or'),
			then: (resolve: (value: unknown) => unknown) =>
				Promise.resolve(
					isCount
						? { count: options.count ?? 0, error: options.countError ?? null }
						: { data: options.rows ?? [], error: options.listError ?? null }
				).then(resolve)
		};
		return self;
	}

	return {
		from: () => ({
			select: (...args: unknown[]) => {
				const isCount = args.length > 1;
				if (!isCount) calls.push({ method: 'select', args });
				return builder(isCount);
			}
		})
	};
}

function event(url = 'http://localhost/api/jafar/notifications') {
	return { url: new URL(url), params: {}, cookies: {} } as Parameters<typeof GET>[0];
}

function session() {
	return {
		email: 'owner@example.com',
		sessionId: 'session-id',
		role: null,
		access: null,
		memberId: null,
		name: null
	};
}

describe('platform owner notifications list API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		calls.length = 0;
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const response = await GET(event());
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects an unknown status filter', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const response = await GET(event('http://localhost/api/jafar/notifications?status=bogus'));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects a limit above the allowed page size', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const response = await GET(event('http://localhost/api/jafar/notifications?limit=5000'));
		expect(response.status).toBe(422);
	});

	it('returns unread notifications and the true unread total by default', async () => {
		mockedOwnerSession.mockResolvedValue(session());
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
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue(clientWith({ rows: [], count: 0 }) as never);

		const response = await GET(event('http://localhost/api/jafar/notifications?status=all'));
		expect(response.status).toBe(200);
		expect(calls).not.toContainEqual({ method: 'is', args: ['read_at', null] });
	});

	it('reads Jafar’s own bell: everything not addressed to a teammate (D3a)', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue(clientWith({ rows: [], count: 0 }) as never);

		await GET(event());
		expect(calls).toContainEqual({ method: 'is', args: ['recipient_member_id', null] });
		expect(calls).toContainEqual({ method: 'countIs', args: ['recipient_member_id', null] });
	});

	it('reads a teammate’s own bell and nothing else (D3a)', async () => {
		mockedOwnerSession.mockResolvedValue({
			...session(),
			email: 'sam@example.com',
			role: 'sales',
			memberId: 'member-sam'
		} as never);
		mockedClient.mockReturnValue(clientWith({ rows: [], count: 0 }) as never);

		await GET(event());
		expect(calls).toContainEqual({ method: 'eq', args: ['recipient_member_id', 'member-sam'] });
		expect(calls).toContainEqual({ method: 'countEq', args: ['recipient_member_id', 'member-sam'] });
		expect(calls.some((call) => call.args[0] === 'recipient_member_id' && call.args[1] === null)).toBe(
			false
		);
	});

	it('searches the title and body of a notification', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue(clientWith({ rows: [], count: 0 }) as never);

		await GET(event('http://localhost/api/jafar/notifications?status=all&search=Ridgeway'));
		expect(calls).toContainEqual({
			method: 'or',
			args: ['title.ilike.%Ridgeway%,body.ilike.%Ridgeway%']
		});
	});

	it('strips filter and wildcard characters so a search term cannot change the query', async () => {
		mockedOwnerSession.mockResolvedValue(session());
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
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue(
			clientWith({ listError: { message: 'internal database details' } }) as never
		);

		const response = await GET(event());
		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'Notifications could not be loaded.' });
	});
});
