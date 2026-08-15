import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const calls: { method: string; args: unknown[] }[] = [];

function query(data: unknown, error: null | { message: string } = null) {
	const builder = {
		select: (...args: unknown[]) => {
			calls.push({ method: 'select', args });
			return builder;
		},
		order: (...args: unknown[]) => {
			calls.push({ method: 'order', args });
			return builder;
		},
		limit: (...args: unknown[]) => {
			calls.push({ method: 'limit', args });
			return builder;
		},
		eq: (...args: unknown[]) => {
			calls.push({ method: 'eq', args });
			return builder;
		},
		neq: (...args: unknown[]) => {
			calls.push({ method: 'neq', args });
			return builder;
		},
		then: (resolve: (value: { data: unknown; error: null | { message: string } }) => unknown) =>
			Promise.resolve({ data, error }).then(resolve)
	};
	return builder;
}

function event(url = 'http://localhost/api/jafar/operations') {
	return { url: new URL(url), params: {}, cookies: {} } as Parameters<typeof GET>[0];
}

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

describe('platform owner operations list API boundary', () => {
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

	it('rejects an invalid status filter', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const response = await GET(event('http://localhost/api/jafar/operations?status=bogus'));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects an invalid target id filter', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const response = await GET(
			event('http://localhost/api/jafar/operations?target_id=not-a-uuid')
		);
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('defaults to every open operation when no status is given', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue({ from: () => query([{ id: 'op-1', status: 'retrying' }]) } as never);

		const response = await GET(event());
		expect(response.status).toBe(200);
		expect((await response.json()).operations[0].id).toBe('op-1');
		expect(calls).toContainEqual({ method: 'neq', args: ['status', 'succeeded'] });
		expect(calls.some((call) => call.method === 'eq' && call.args[0] === 'status')).toBe(false);
	});

	it('filters by the requested status instead of the open-only default', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue({ from: () => query([{ id: 'op-2', status: 'acknowledged' }]) } as never);

		const response = await GET(
			event('http://localhost/api/jafar/operations?status=acknowledged')
		);
		expect(response.status).toBe(200);
		expect(calls).toContainEqual({ method: 'eq', args: ['status', 'acknowledged'] });
		expect(calls.some((call) => call.method === 'neq')).toBe(false);
	});

	// A notification can link to an attempt that has since succeeded, so the panel needs a way
	// to ask for every status without naming one.
	it('applies no status filter at all when every status is asked for', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue({ from: () => query([{ id: 'op-3', status: 'succeeded' }]) } as never);

		const response = await GET(event('http://localhost/api/jafar/operations?status=all'));
		expect(response.status).toBe(200);
		expect(calls.some((call) => call.method === 'neq')).toBe(false);
		expect(calls.some((call) => call.method === 'eq' && call.args[0] === 'status')).toBe(false);
	});

	it('filters by target id when provided', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue({ from: () => query([]) } as never);

		const targetId = '123e4567-e89b-12d3-a456-426614174000';
		const response = await GET(event(`http://localhost/api/jafar/operations?target_id=${targetId}`));
		expect(response.status).toBe(200);
		expect(calls).toContainEqual({ method: 'eq', args: ['target_id', targetId] });
	});

	it('returns a safe server error when the operations query fails', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue({
			from: () => query(null, { message: 'internal database details' })
		} as never);

		const response = await GET(event());
		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'Operations could not be loaded.' });
	});
});
