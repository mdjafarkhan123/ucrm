import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DELETE, GET, PATCH } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// D3b: each person's calendar entries are their own; calls follow the Leads & Deals area.

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const ID = '11111111-1111-4111-8111-111111111111';
type Session = Awaited<ReturnType<typeof getOwnerSession>>;
const jafar = { email: 'jafar@example.com', role: null, access: null, memberId: null } as Session;
const sam = {
	email: 'sam@example.com',
	role: 'sales',
	access: null,
	memberId: 'member-sam'
} as Session;
const sue = {
	email: 'sue@example.com',
	role: 'support',
	access: null,
	memberId: 'member-sue'
} as Session;

function client(entry: unknown) {
	const rpc = vi.fn(async (name: string) =>
		name === 'owner_calendar_entry' ? { data: entry, error: null } : { data: true, error: null }
	);
	mockedClient.mockReturnValue({ rpc } as unknown as ReturnType<typeof getOwnerSupabaseClient>);
	return rpc;
}

function event(body?: unknown) {
	return {
		params: { id: ID },
		url: new URL('http://localhost'),
		request: new Request('http://localhost', {
			method: body ? 'PATCH' : 'GET',
			body: body ? JSON.stringify(body) : undefined
		})
	} as unknown as Parameters<typeof GET>[0];
}

const MOVE = {
	action: 'move',
	starts_at: '2026-10-12T10:00:00.000Z',
	ends_at: '2026-10-12T10:30:00.000Z'
};

beforeEach(() => {
	vi.clearAllMocks();
	vi.spyOn(console, 'error').mockImplementation(() => {});
});

describe('/api/jafar/calendar/entries/[id]', () => {
	it("hides someone else's Busy block, even from Jafar", async () => {
		mockedSession.mockResolvedValue(jafar);
		client({ kind: 'busy', owner_member_id: 'member-sam' });
		expect((await GET(event())).status).toBe(404);
	});

	it('lets a Sales teammate open and move a call', async () => {
		mockedSession.mockResolvedValue(sam);
		const rpc = client({ kind: 'call', owner_member_id: 'member-sam' });
		expect((await GET(event())).status).toBe(200);
		expect((await PATCH(event(MOVE))).status).toBe(200);
		expect(rpc).toHaveBeenCalledWith(
			'owner_calendar_move',
			expect.objectContaining({ target_id: ID })
		);
	});

	it('refuses calls to a teammate without Leads & Deals', async () => {
		mockedSession.mockResolvedValue(sue);
		const rpc = client({ kind: 'call', owner_member_id: null });
		expect((await GET(event())).status).toBe(404);
		expect((await PATCH(event(MOVE))).status).toBe(404);
		expect(rpc).not.toHaveBeenCalledWith('owner_calendar_move', expect.anything());
	});

	it('lets anyone move their own Busy block but asks the database for only theirs on removal', async () => {
		mockedSession.mockResolvedValue(sue);
		const rpc = client({ kind: 'busy', owner_member_id: 'member-sue' });
		expect((await PATCH(event(MOVE))).status).toBe(200);
		expect((await DELETE(event())).status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_calendar_delete_busy', {
			target_id: ID,
			viewer_member_id: 'member-sue'
		});
	});
});
