import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as approve } from './+server';
import { POST as sendBack } from './send-back/+server';
import { POST as doNotContact } from '../do-not-contact/+server';
import { POST as clearDoNotContact } from '../do-not-contact/clear/+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const LEAD_ID = '6f1c2a5e-8b8e-4f4e-9d3c-1a2b3c4d5e6f';
const EMAIL_ID = '11111111-2222-4333-8444-555555555555';
const WHATSAPP_ID = '22222222-3333-4444-8555-666666666666';

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

function post(path: string, body: unknown, id = LEAD_ID): never {
	const url = `http://localhost/api/jafar/leads/${id}/${path}`;
	return {
		url: new URL(url),
		params: { id },
		cookies: {},
		request: new Request(url, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		})
	} as never;
}

describe('Approving who to contact', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		signedIn();
	});

	it('refuses someone who is not signed in', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const response = await approve(
			post('approval', { method_ids: [EMAIL_ID], due_on: '2026-10-07' })
		);
		expect(response.status).toBe(401);
	});

	it('approves the chosen details with the first-contact day', async () => {
		const rpc = rpcReturning('approved');
		const response = await approve(
			post('approval', {
				method_ids: [EMAIL_ID, WHATSAPP_ID],
				whatsapp_permission_ids: [WHATSAPP_ID],
				due_on: '2026-10-07'
			})
		);
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_lead_approve', {
			actor_email: 'owner@example.com',
			target_id: LEAD_ID,
			method_ids: [EMAIL_ID, WHATSAPP_ID],
			whatsapp_permission_ids: [WHATSAPP_ID],
			task_due_on: '2026-10-07'
		});
	});

	it('needs at least one detail and a real date', async () => {
		const rpc = rpcReturning('approved');
		const response = await approve(post('approval', { method_ids: [], due_on: '2026-02-30' }));
		expect(response.status).toBe(422);
		const body = await response.json();
		expect(Object.keys(body.field_errors)).toEqual(
			expect.arrayContaining(['method_ids', 'due_on'])
		);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses WhatsApp permission for a number that is not being approved', async () => {
		const rpc = rpcReturning('approved');
		const response = await approve(
			post('approval', {
				method_ids: [EMAIL_ID],
				whatsapp_permission_ids: [WHATSAPP_ID],
				due_on: '2026-10-07'
			})
		);
		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('passes on the database’s refusal in its own words', async () => {
		rpcReturning(null, { code: '22023', message: 'This business asked not to be contacted.' });
		const response = await approve(
			post('approval', { method_ids: [EMAIL_ID], due_on: '2026-10-07' })
		);
		expect(response.status).toBe(409);
		expect(JSON.stringify(await response.json())).toContain(
			'This business asked not to be contacted.'
		);
	});

	it('says when the Lead has gone', async () => {
		rpcReturning('lead_not_found');
		const response = await approve(
			post('approval', { method_ids: [EMAIL_ID], due_on: '2026-10-07' })
		);
		expect(response.status).toBe(404);
	});

	it('sends a Lead back with what needs fixing', async () => {
		const rpc = rpcReturning('sent_back');
		const response = await sendBack(
			post('approval/send-back', { reason: '  Find the owner’s name ' })
		);
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_lead_send_back', {
			actor_email: 'owner@example.com',
			target_id: LEAD_ID,
			reason: 'Find the owner’s name'
		});
		expect((await sendBack(post('approval/send-back', { reason: ' ' }))).status).toBe(422);
	});

	it('records and lifts Do not contact', async () => {
		const rpc = rpcReturning('updated');
		expect((await doNotContact(post('do-not-contact', { reason: 'Said stop' }))).status).toBe(200);
		expect(rpc).toHaveBeenLastCalledWith('owner_lead_set_do_not_contact', {
			actor_email: 'owner@example.com',
			target_id: LEAD_ID,
			turn_on: true,
			reason: 'Said stop'
		});
		expect((await clearDoNotContact(post('do-not-contact/clear', {}))).status).toBe(200);
		expect(rpc).toHaveBeenLastCalledWith('owner_lead_set_do_not_contact', {
			actor_email: 'owner@example.com',
			target_id: LEAD_ID,
			turn_on: false,
			reason: undefined
		});
	});

	it('treats a bad Lead id as not found', async () => {
		const rpc = rpcReturning('approved');
		const response = await approve(
			post('approval', { method_ids: [EMAIL_ID], due_on: '2026-10-07' }, 'not-a-uuid')
		);
		expect(response.status).toBe(404);
		expect(rpc).not.toHaveBeenCalled();
	});
});
