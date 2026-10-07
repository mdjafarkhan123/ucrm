import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, PATCH } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const MEMBER_ID = '77777777-7777-4777-8777-777777777777';
const owner = {
	email: 'owner@example.com',
	sessionId: 's1',
	role: null,
	access: null,
	memberId: null,
	name: null
};
const teammate = {
	email: 'sam@uplift.example',
	sessionId: 's2',
	role: 'sales' as const,
	access: { areas: { leads: 'work' as const }, actions: [] },
	memberId: MEMBER_ID,
	name: 'Sam Seller'
};

type MemberRow = {
	id: string;
	email: string;
	full_name: string | null;
	role: string;
	status: string;
	access_revision: number;
	area_adjustments: unknown;
	action_grants: string[];
};

function fakeClient(options: { member: MemberRow | null; rpcRows?: { access_revision: number }[] }) {
	const rpc = vi.fn(async () => ({ data: options.rpcRows ?? [], error: null }));
	const builder = (result: unknown) => {
		const chain: Record<string, unknown> = {
			select: () => chain,
			eq: () => chain,
			neq: () => chain,
			order: () => chain,
			limit: () => Promise.resolve(result),
			maybeSingle: () => Promise.resolve(result)
		};
		return chain;
	};
	const client = {
		rpc,
		from: (table: string) =>
			table === 'platform_team_members'
				? builder({ data: options.member, error: null })
				: builder({
						data: [
							{
								id: 'e1',
								event_type: 'team_member_invited',
								actor_owner_email: 'owner@example.com',
								created_at: '2026-10-07T10:00:00Z',
								before_state: null,
								after_state: { role: 'sales' }
							}
						],
						error: null
					})
	};
	mockedClient.mockReturnValue(client as never);
	return client;
}

const sam: MemberRow = {
	id: MEMBER_ID,
	email: 'sam@uplift.example',
	full_name: 'Sam Seller',
	role: 'sales',
	status: 'active',
	access_revision: 3,
	area_adjustments: { applications: 'work' },
	action_grants: ['payments']
};

function event(method: 'GET' | 'PATCH', body?: unknown, memberId = MEMBER_ID) {
	const url = `http://localhost/api/jafar/team/${memberId}/access`;
	return {
		params: { memberId },
		url: new URL(url),
		cookies: {},
		request: new Request(url, {
			method,
			...(body === undefined
				? {}
				: { body: JSON.stringify(body), headers: { 'content-type': 'application/json' } })
		})
	} as unknown as Parameters<typeof PATCH>[0];
}

const validSave = {
	role: 'sales',
	areas: { leads: 'work', applications: 'look' },
	actions: ['payments'],
	expected_access_revision: 3
};

describe('/api/jafar/team/[memberId]/access', () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it('refuses anyone but the owner', async () => {
		mockedOwnerSession.mockResolvedValue(teammate);
		expect((await GET(event('GET'))).status).toBe(401);
		expect((await PATCH(event('PATCH', validSave))).status).toBe(401);
		mockedOwnerSession.mockResolvedValue(null);
		expect((await GET(event('GET'))).status).toBe(401);
	});

	it('shows the role, the adjustments, the access they add up to, and the history', async () => {
		mockedOwnerSession.mockResolvedValue(owner);
		fakeClient({ member: sam });
		const response = await GET(event('GET'));
		expect(response.status).toBe(200);
		const body = await response.json();
		expect(body.member).toMatchObject({ role: 'sales', access_revision: 3 });
		expect(body.access).toEqual({
			areas: { leads: 'work', applications: 'work' },
			actions: ['payments']
		});
		expect(body.history[0]).toMatchObject({
			event_type: 'team_member_invited',
			actor_email: 'owner@example.com'
		});
	});

	it('answers 404 for a removed or unknown teammate', async () => {
		mockedOwnerSession.mockResolvedValue(owner);
		fakeClient({ member: null });
		expect((await GET(event('GET'))).status).toBe(404);
		expect((await GET(event('GET', undefined, 'not-a-uuid'))).status).toBe(404);
	});

	it('stores only what differs from the role, as the owner', async () => {
		mockedOwnerSession.mockResolvedValue(owner);
		const client = fakeClient({ member: sam, rpcRows: [{ access_revision: 4 }] });
		const response = await PATCH(event('PATCH', validSave));
		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith('platform_team_set_access', {
			p_member_id: MEMBER_ID,
			p_expected_revision: 3,
			p_role: 'sales',
			p_area_adjustments: {},
			p_action_grants: ['payments'],
			p_actor_email: 'owner@example.com'
		});
	});

	it('refuses access with no area, or an action whose area is closed', async () => {
		mockedOwnerSession.mockResolvedValue(owner);
		const client = fakeClient({ member: sam });
		const empty = await PATCH(event('PATCH', { ...validSave, areas: {}, actions: [] }));
		expect(empty.status).toBe(422);
		expect((await empty.json()).error).toMatch(/at least one area/);

		const orphan = await PATCH(
			event('PATCH', { ...validSave, areas: { leads: 'work' }, actions: ['payments'] })
		);
		expect(orphan.status).toBe(422);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('refuses unknown areas, levels, and actions', async () => {
		mockedOwnerSession.mockResolvedValue(owner);
		const client = fakeClient({ member: sam });
		for (const body of [
			{ ...validSave, areas: { settings: 'work' } },
			{ ...validSave, areas: { leads: 'admin' } },
			{ ...validSave, actions: ['manage_team'] },
			{ ...validSave, role: 'owner' },
			{ ...validSave, expected_access_revision: -1 }
		]) {
			expect((await PATCH(event('PATCH', body))).status, JSON.stringify(body)).toBe(422);
		}
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('answers 409 when someone saved a newer version first', async () => {
		mockedOwnerSession.mockResolvedValue(owner);
		fakeClient({ member: sam, rpcRows: [] });
		const response = await PATCH(event('PATCH', validSave));
		expect(response.status).toBe(409);
		expect((await response.json()).code).toBe('stale');
	});
});
