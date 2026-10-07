import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const LEAD_ID = '6f1c2a5e-8b8e-4f4e-9d3c-1a2b3c4d5e6f';
const METHOD_ID = '11111111-2222-4333-8444-555555555555';

function signedIn() {
	mockedOwnerSession.mockResolvedValue({
		email: 'owner@example.com',
		sessionId: 'session-id',
		role: null,
		access: null,
		memberId: null,
		name: null
	});
}

function rpcReturning(data: unknown, error: unknown = null) {
	const rpc = vi.fn().mockResolvedValue({ data, error });
	mockedClient.mockReturnValue({ rpc } as unknown as ReturnType<typeof getOwnerSupabaseClient>);
	return rpc;
}

function patch(body: unknown, id = LEAD_ID): never {
	const url = `http://localhost/api/jafar/leads/${id}/details`;
	return {
		url: new URL(url),
		params: { id },
		cookies: {},
		request: new Request(url, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		})
	} as never;
}

describe('Editing a Lead’s details', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		signedIn();
	});

	it('refuses someone who is not signed in', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const response = await PATCH(patch({ fields: { trade: 'Plumbing' } }));
		expect(response.status).toBe(401);
	});

	it('sends only the fields being changed, with a cleared optional field as empty', async () => {
		const rpc = rpcReturning('updated');
		const response = await PATCH(
			patch({ fields: { business_name: '  Smith Plumbing ', website: '' } })
		);
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ result: 'updated' });
		expect(rpc).toHaveBeenCalledWith('owner_lead_update_details', {
			actor_email: 'owner@example.com',
			target_id: LEAD_ID,
			fields: { business_name: 'Smith Plumbing', website: null },
			contact_methods: { add: [], change: [], remove: [] }
		});
	});

	it('corrects a contact detail in place, keeping its id', async () => {
		const rpc = rpcReturning('updated');
		const change = {
			id: METHOD_ID,
			kind: 'email',
			value: 'info@smithplumbing.co.uk',
			found_at: 'Contact page'
		};
		await PATCH(patch({ contact_methods: { change: [change] } }));
		expect(rpc.mock.calls[0][1].contact_methods).toEqual({ add: [], change: [change], remove: [] });
	});

	it('checks a corrected email and a new phone number like the add form does', async () => {
		const rpc = rpcReturning('updated');
		const response = await PATCH(
			patch({
				contact_methods: {
					change: [{ id: METHOD_ID, kind: 'email', value: 'info@smith', found_at: 'Site' }],
					add: [{ kind: 'phone', value: '123', found_at: 'Site' }]
				}
			})
		);
		expect(response.status).toBe(422);
		const result = await response.json();
		expect(result.field_errors['contact_methods.change.0.value']).toBe(
			'Enter a valid email address.'
		);
		expect(result.field_errors['contact_methods.add.0.value']).toBe(
			'Enter the full phone number, with its country code.'
		);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses an empty save, an unknown field, a blank required field, and change-and-remove of one detail', async () => {
		const rpc = rpcReturning('updated');
		for (const body of [
			{},
			{ fields: { lead_status: 'later' } },
			{ fields: { business_name: '  ' } },
			{
				contact_methods: {
					change: [{ id: METHOD_ID, kind: 'email', value: 'a@b.co', found_at: 'Site' }],
					remove: [METHOD_ID]
				}
			}
		]) {
			const response = await PATCH(patch(body));
			expect(response.status).toBe(422);
		}
		expect(rpc).not.toHaveBeenCalled();
	});

	it('passes the database’s plain refusal back to the form', async () => {
		rpcReturning(null, {
			code: '22023',
			message: 'A Lead can have at most ten contact details.'
		});
		const response = await PATCH(
			patch({ contact_methods: { add: [{ kind: 'email', value: 'a@b.co', found_at: 'Site' }] } })
		);
		expect(response.status).toBe(409);
		expect((await response.json()).field_errors.form).toBe(
			'A Lead can have at most ten contact details.'
		);
	});

	it('says when the Lead is gone', async () => {
		rpcReturning('lead_not_found');
		const response = await PATCH(patch({ fields: { trade: 'Roofing' } }));
		expect(response.status).toBe(404);
		const bad = await PATCH(patch({ fields: { trade: 'Roofing' } }, 'not-a-uuid'));
		expect(bad.status).toBe(404);
	});
});
