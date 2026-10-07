import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const BUSINESS_ID = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
const DELIVERY_ID = '6f1c2a5e-8b8e-4f4e-9d3c-1a2b3c4d5e6f';
const SALES_ID = '1b2c3d4e-5f6a-4b7c-8d9e-0f1a2b3c4d5e';

const TEAM = [
	// Delivery opens Onboarding by its role.
	{
		id: DELIVERY_ID,
		email: 'dee@example.com',
		full_name: 'Dee Delivery',
		avatar_url: null,
		role: 'delivery',
		area_adjustments: {},
		action_grants: []
	},
	// Sales does not, unless Jafar opens it.
	{
		id: SALES_ID,
		email: 'sam@example.com',
		full_name: 'Sam Seller',
		avatar_url: null,
		role: 'sales',
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
	const url = `http://localhost/api/jafar/leads/${BUSINESS_ID}/setup-owner`;
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

describe('who looks after setup (B5)', () => {
	it('offers only active teammates who can open Onboarding', async () => {
		signedIn();
		database();
		const response = await GET(event());
		expect(response.status).toBe(200);
		expect((await response.json()).choices).toEqual([
			{ id: DELIVERY_ID, name: 'Dee Delivery', avatar_url: null }
		]);
	});

	it('is Jafar’s choice alone', async () => {
		signedIn('sales');
		const rpc = database();
		expect((await GET(event())).status).toBe(401);
		expect((await POST(event({ member_id: null }))).status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('hands setup to a teammate with Onboarding access', async () => {
		signedIn();
		const rpc = database();
		const response = await POST(event({ member_id: DELIVERY_ID }));
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_business_set_setup_owner', {
			actor_email: 'owner@example.com',
			target_relationship_id: BUSINESS_ID,
			target_member_id: DELIVERY_ID
		});
	});

	it('refuses a teammate who cannot open Onboarding', async () => {
		signedIn();
		const rpc = database();
		const response = await POST(event({ member_id: SALES_ID }));
		expect(response.status).toBe(409);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('gives setup back to Jafar', async () => {
		signedIn();
		const rpc = database();
		expect((await POST(event({ member_id: null }))).status).toBe(200);
		expect(rpc).toHaveBeenCalledWith(
			'owner_business_set_setup_owner',
			expect.objectContaining({ target_member_id: null })
		);
	});

	it('says why the database refused, in its words', async () => {
		signedIn();
		database({
			data: null,
			error: { code: '22023', message: 'Setup is looked after once the business has paid.' }
		});
		const response = await POST(event({ member_id: null }));
		expect(response.status).toBe(409);
		expect(JSON.stringify(await response.json())).toContain('once the business has paid');
	});
});
