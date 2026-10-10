import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as live } from './+server';
import { GET as ready } from './ready/+server';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedClient = vi.mocked(getOwnerSupabaseClient);

function databaseAnswers(error: unknown) {
	mockedClient.mockReturnValue({
		from: () => ({ select: () => ({ limit: () => Promise.resolve({ error }) }) })
	} as never);
}

describe('health routes', () => {
	beforeEach(() => {
		vi.spyOn(console, 'error').mockImplementation(() => {});
	});

	it('liveness answers ok without touching the database', async () => {
		const response = await live({} as never);
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ status: 'ok' });
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('readiness is ready when the database answers', async () => {
		databaseAnswers(null);
		const response = await ready({} as never);
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ status: 'ready' });
	});

	it('readiness is unavailable, with no error text, when the database fails', async () => {
		databaseAnswers({ message: 'connection refused to db.internal:5432' });
		const response = await ready({} as never);
		expect(response.status).toBe(503);
		const body = await response.text();
		expect(JSON.parse(body)).toEqual({ status: 'unavailable' });
		expect(body).not.toContain('db.internal');
	});
});
