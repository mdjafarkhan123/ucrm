import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { canUseJafarPath } from '$lib/jafar/team-access';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const BUSINESS_ID = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
const SALES_ID = '1b2c3d4e-5f6a-4b7c-8d9e-0f1a2b3c4d5e';
const LOOKER_ID = '2c3d4e5f-6a7b-4c8d-9e0f-1a2b3c4d5e6f';
const DELIVERY_ID = '6f1c2a5e-8b8e-4f4e-9d3c-1a2b3c4d5e6f';

const TEAM = [
	// Sales changes Leads by its role.
	{
		id: SALES_ID,
		email: 'sam@example.com',
		full_name: 'Sam Seller',
		avatar_url: null,
		role: 'sales',
		area_adjustments: {},
		action_grants: []
	},
	// Jafar let this one only look at Leads.
	{
		id: LOOKER_ID,
		email: 'lou@example.com',
		full_name: 'Lou Looker',
		avatar_url: null,
		role: 'sales',
		area_adjustments: { leads: 'look' },
		action_grants: []
	},
	// Delivery has no Leads at all.
	{
		id: DELIVERY_ID,
		email: 'dee@example.com',
		full_name: 'Dee Delivery',
		avatar_url: null,
		role: 'delivery',
		area_adjustments: {},
		action_grants: []
	}
];

function signedIn(role: 'sales' | null = null) {
	mockedOwnerSession.mockResolvedValue({
		email: role ? 'sam@example.com' : 'owner@example.com',
		sessionId: 'session-id',
		role,
		access: null,
		memberId: role ? SALES_ID : null,
		name: null
	});
}

function database(rpcResult: { data: unknown; error: unknown } = { data: true, error: null }) {
	const rpc = vi.fn().mockResolvedValue(rpcResult);
	const query = {
		select: vi.fn().mockReturnThis(),
		eq: vi.fn().mockReturnThis(),
		is: vi.fn().mockResolvedValue({ data: TEAM, error: null })
	};
	mockedClient.mockReturnValue({
		rpc,
		from: vi.fn(() => query)
	} as unknown as ReturnType<typeof getOwnerSupabaseClient>);
	return rpc;
}

function event(body?: unknown): never {
	const url = `http://localhost/api/jafar/leads/${BUSINESS_ID}/owner`;
	return {
		url: new URL(url),
		params: { id: BUSINESS_ID },
		cookies: {},
		request: new Request(url, {
			method: body === undefined ? 'GET' : 'POST',
			headers: { 'content-type': 'application/json' },
			body: body === undefined ? undefined : JSON.stringify(body)
		})
	} as never;
}

beforeEach(() => vi.clearAllMocks());

describe('who owns a Lead (D3a)', () => {
	it('offers only active teammates who can change Leads & Deals', async () => {
		signedIn();
		database();
		const response = await GET(event());
		expect(response.status).toBe(200);
		expect((await response.json()).choices).toEqual([
			{ id: SALES_ID, name: 'Sam Seller', avatar_url: null }
		]);
	});

	it('hands the Lead to a teammate, recording who did it', async () => {
		signedIn('sales');
		const rpc = database();
		const response = await POST(event({ member_id: SALES_ID }));
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_lead_set_owner', {
			actor_email: 'sam@example.com',
			target_relationship_id: BUSINESS_ID,
			target_member_id: SALES_ID
		});
	});

	it('refuses a teammate who can only look at Leads', async () => {
		signedIn();
		const rpc = database();
		expect((await POST(event({ member_id: LOOKER_ID }))).status).toBe(409);
		expect((await POST(event({ member_id: DELIVERY_ID }))).status).toBe(409);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('gives the Lead back to Jafar', async () => {
		signedIn();
		const rpc = database();
		expect((await POST(event({ member_id: null }))).status).toBe(200);
		expect(rpc).toHaveBeenCalledWith(
			'owner_lead_set_owner',
			expect.objectContaining({ target_member_id: null })
		);
	});

	it('says the Lead is gone when it no longer exists', async () => {
		signedIn();
		database({ data: false, error: null });
		expect((await POST(event({ member_id: null }))).status).toBe(404);
	});

	it('is Leads work at the gate: a looker cannot change the owner', () => {
		const path = `/api/jafar/leads/${BUSINESS_ID}/owner`;
		const looker = {
			role: 'sales' as const,
			access: { areas: { leads: 'look' as const }, actions: [] }
		};
		expect(canUseJafarPath(looker, path, 'GET')).toBe(true);
		expect(canUseJafarPath(looker, path, 'POST')).toBe(false);
		expect(canUseJafarPath({ role: 'sales' }, path, 'POST')).toBe(true);
		expect(canUseJafarPath({ role: 'delivery' }, path, 'GET')).toBe(false);
	});
});
