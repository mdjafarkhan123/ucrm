import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

function call(params: Record<string, string>) {
	const url = new URL('http://localhost/api/jafar/leads/report');
	for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
	return GET({ url } as unknown as Parameters<typeof GET>[0]);
}

function client(result: { data?: unknown; error?: unknown }) {
	const rpc = vi.fn(async () => result);
	mockedClient.mockReturnValue({ rpc } as unknown as ReturnType<typeof getOwnerSupabaseClient>);
	return rpc;
}

function signIn(memberId: string | null) {
	mockedSession.mockResolvedValue({
		email: 'someone@example.com',
		role: memberId ? 'sales' : null,
		access: null,
		memberId
	} as Awaited<ReturnType<typeof getOwnerSession>>);
}

beforeEach(() => {
	vi.clearAllMocks();
	vi.spyOn(console, 'error').mockImplementation(() => {});
	signIn(null);
});

describe('GET /api/jafar/leads/report', () => {
	it('refuses someone who is not signed in', async () => {
		mockedSession.mockResolvedValue(null);
		expect((await call({ to: '2026-10-09' })).status).toBe(401);
	});

	it('refuses missing, malformed or backwards dates before touching the database', async () => {
		const rpc = client({ data: null });
		expect((await call({})).status).toBe(422);
		expect((await call({ to: '09/10/2026' })).status).toBe(422);
		expect((await call({ from: '2026-10-10', to: '2026-10-09' })).status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('reads the period in the viewer’s own time zone', async () => {
		const report = { time_zone: 'Europe/London', sources: [] };
		const rpc = client({ data: report, error: null });
		signIn('7d1c0b52-8a4f-4f36-9a51-1f6c2a0d9e11');
		const response = await call({ from: '2026-10-01', to: '2026-10-09' });
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual(report);
		expect(rpc).toHaveBeenCalledWith('owner_activity_report', {
			from_date: '2026-10-01',
			to_date: '2026-10-09',
			viewer_member_id: '7d1c0b52-8a4f-4f36-9a51-1f6c2a0d9e11'
		});
	});

	it('reads all time for Jafar when no start is given', async () => {
		const rpc = client({ data: { time_zone: 'UTC', sources: [] }, error: null });
		expect((await call({ to: '2026-10-09' })).status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_activity_report', {
			from_date: null,
			to_date: '2026-10-09',
			viewer_member_id: undefined
		});
	});

	it('says the report could not be loaded when the database fails', async () => {
		client({ data: null, error: new Error('down') });
		expect((await call({ to: '2026-10-09' })).status).toBe(500);
	});
});
