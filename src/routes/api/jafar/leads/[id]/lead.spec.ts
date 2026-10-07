import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as GET_PAGE, PATCH as CHANGE_LEAD } from './+server';
import { GET as GET_HISTORY, POST as ADD_HISTORY } from './history/+server';
import { PATCH as EDIT_ENTRY, DELETE as DELETE_ENTRY } from './history/[entryId]/+server';
import { POST as LINK_APPLICATION } from './applications/+server';
import { DELETE as UNLINK_APPLICATION } from './applications/[applicationId]/+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { encodeHistoryCursor } from '$lib/server/jafar/lead-history';

vi.mock('$lib/server/auth/owner', () => ({
	getOwnerSession: vi.fn(),
	isOwnerEmail: (email: string) => email === 'owner@example.com'
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const LEAD_ID = '6f1c2a5e-8b8e-4f4e-9d3c-1a2b3c4d5e6f';
const ENTRY_ID = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
const APPLICATION_ID = '9d8c7b6a-5f4e-4d3c-8b2a-1f0e9d8c7b6a';
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

// A stand-in for `.from(table)` whose every filter returns itself and which resolves to `result` at the end.
function tableReturning(result: { data: unknown; error: unknown }) {
	const calls: Record<string, unknown[][]> = {};
	const chain: Record<string, unknown> = {};
	for (const name of ['insert', 'update', 'delete', 'select', 'eq', 'in']) {
		chain[name] = (...args: unknown[]) => {
			(calls[name] ??= []).push(args);
			return chain;
		};
	}
	chain.single = () => Promise.resolve(result);
	chain.then = (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve);
	const from = vi.fn().mockReturnValue(chain);
	mockedClient.mockReturnValue({ from } as unknown as ReturnType<typeof getOwnerSupabaseClient>);
	return { from, calls };
}

function event(
	params: Record<string, string>,
	options: { method?: string; body?: unknown; url?: string } = {}
): never {
	const url = options.url ?? `http://localhost/api/jafar/leads/${params.id}`;
	return {
		url: new URL(url),
		params,
		cookies: {},
		request: new Request(url, {
			method: options.method ?? 'GET',
			headers: { 'content-type': 'application/json' },
			body: options.body === undefined ? undefined : JSON.stringify(options.body)
		})
	} as never;
}

const minutesAgo = (minutes: number) => new Date(Date.now() - minutes * 60_000).toISOString();

describe('Lead page GET', () => {
	beforeEach(() => vi.clearAllMocks());

	it('refuses a caller who is not signed in', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const response = await GET_PAGE(event({ id: LEAD_ID }));
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('answers "no longer exists" for an id that is not a Lead id', async () => {
		signedIn();
		const response = await GET_PAGE(event({ id: 'not-a-lead' }));
		expect(response.status).toBe(404);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('answers "no longer exists" when the database finds no Lead', async () => {
		signedIn();
		rpcReturning(null);
		expect((await GET_PAGE(event({ id: LEAD_ID }))).status).toBe(404);
	});

	it('names who did each thing and hides the cursor behind an opaque string', async () => {
		signedIn();
		const rpc = rpcReturning({
			lead: { id: LEAD_ID },
			contact_methods: [],
			applications: [],
			last_contacted_at: null,
			last_heard_from_at: null,
			history: {
				entries: [
					{ id: 'a', kind: 'note', actor_email: 'owner@example.com', actor_name: null },
					{ id: 'b', kind: 'note', actor_email: 'sam@example.com', actor_name: 'Sam Seller' },
					{ id: 'c', kind: 'note', actor_email: 'new@example.com', actor_name: null },
					{ id: 'd', kind: 'application_submitted', actor_email: null, actor_name: null }
				],
				next_cursor: { occurred_at: '2026-10-07T03:00:00Z', id: ENTRY_ID }
			}
		});
		const response = await GET_PAGE(event({ id: LEAD_ID }));
		expect(rpc).toHaveBeenCalledWith('owner_lead_page', { target_id: LEAD_ID });
		const page = await response.json();
		expect(page.history.entries.map((entry: { actor: string | null }) => entry.actor)).toEqual([
			'Jafar',
			'Sam Seller',
			'new@example.com',
			null
		]);
		expect(page.history.entries[0]).not.toHaveProperty('actor_email');
		expect(typeof page.history.next_cursor).toBe('string');
		expect(response.headers.get('cache-control')).toContain('private');
	});
});

describe('Changing a Lead', () => {
	beforeEach(() => vi.clearAllMocks());

	const change = (body: unknown) => CHANGE_LEAD(event({ id: LEAD_ID }, { method: 'PATCH', body }));

	it('refuses a change that changes nothing', async () => {
		signedIn();
		const response = await change({});
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('refuses marking the next action done with a new one but no due date', async () => {
		signedIn();
		const response = await change({ next_action: { mode: 'done', text: 'Call back' } });
		expect(response.status).toBe(422);
		expect((await response.json()).field_errors['next_action.due_on']).toBe(
			'Choose when the next action is due.'
		);
	});

	it('marks the next action done and sets the next one, in one database call', async () => {
		signedIn();
		const rpc = rpcReturning(true);
		const response = await change({
			lead_status: 'ready_for_review',
			next_action: { mode: 'done', text: 'Send pricing link', due_on: '2026-10-09' }
		});
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_lead_change', {
			actor_email: 'owner@example.com',
			target_id: LEAD_ID,
			target_status: 'ready_for_review',
			next_action_mode: 'done',
			target_next_action: 'Send pricing link',
			target_due_on: '2026-10-09'
		});
	});

	it('keeps the next action when only the status changes', async () => {
		signedIn();
		const rpc = rpcReturning(true);
		await change({ lead_status: 'later' });
		expect(rpc).toHaveBeenCalledWith(
			'owner_lead_change',
			expect.objectContaining({ next_action_mode: 'keep', target_next_action: undefined })
		);
	});

	it("shows the database's own refusal in its words", async () => {
		signedIn();
		rpcReturning(null, { code: '22023', message: 'There is no next action to mark done.' });
		const response = await change({ next_action: { mode: 'done' } });
		expect(response.status).toBe(409);
		expect((await response.json()).field_errors.form).toBe('There is no next action to mark done.');
	});
});

describe('Lead history', () => {
	beforeEach(() => vi.clearAllMocks());

	const add = (body: unknown) =>
		ADD_HISTORY(
			event(
				{ id: LEAD_ID },
				{ method: 'POST', body, url: `http://localhost/api/jafar/leads/${LEAD_ID}/history` }
			)
		);

	it('refuses an older-history request with a cursor it did not issue', async () => {
		signedIn();
		const response = await GET_HISTORY(
			event(
				{ id: LEAD_ID },
				{ url: `http://localhost/api/jafar/leads/${LEAD_ID}/history?cursor=made-up` }
			)
		);
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('loads older history from the place its cursor points to', async () => {
		signedIn();
		const rpc = rpcReturning({ entries: [], next_cursor: null });
		const cursor = encodeHistoryCursor({ occurred_at: '2026-10-07T03:00:00Z', id: ENTRY_ID });
		const response = await GET_HISTORY(
			event(
				{ id: LEAD_ID },
				{ url: `http://localhost/api/jafar/leads/${LEAD_ID}/history?cursor=${cursor}` }
			)
		);
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_lead_history', {
			target_id: LEAD_ID,
			cursor_occurred_at: '2026-10-07T03:00:00Z',
			cursor_id: ENTRY_ID,
			page_size: 50
		});
	});

	it('adds a note with the signed-in person as its author', async () => {
		signedIn();
		const { from, calls } = tableReturning({ data: { id: ENTRY_ID }, error: null });
		const response = await add({ kind: 'note', body: '  Owner prefers mornings  ' });
		expect(response.status).toBe(201);
		expect(from).toHaveBeenCalledWith('platform_business_history');
		expect(calls.insert[0][0]).toMatchObject({
			kind: 'note',
			body: 'Owner prefers mornings',
			relationship_id: LEAD_ID,
			actor_email: 'owner@example.com',
			contact_channel: null
		});
	});

	it('logs an email sent from Gmail with the address it went to', async () => {
		signedIn();
		const { calls } = tableReturning({ data: { id: ENTRY_ID }, error: null });
		const occurred = minutesAgo(30);
		const response = await add({
			kind: 'contact',
			contact_direction: 'outbound',
			contact_channel: 'email',
			contact_method_id: METHOD_ID,
			occurred_at: occurred,
			body: 'Sent the intro email from Gmail'
		});
		expect(response.status).toBe(201);
		expect(calls.insert[0][0]).toMatchObject({
			kind: 'contact',
			contact_direction: 'outbound',
			contact_channel: 'email',
			contact_method_id: METHOD_ID,
			occurred_at: occurred,
			call_outcome: null
		});
	});

	it('asks how a call we made went', async () => {
		signedIn();
		const response = await add({
			kind: 'contact',
			contact_direction: 'outbound',
			contact_channel: 'phone',
			occurred_at: minutesAgo(5)
		});
		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.call_outcome).toBe('Choose how the call went.');
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('refuses an outcome on a reply', async () => {
		signedIn();
		const response = await add({
			kind: 'contact',
			contact_direction: 'inbound',
			contact_channel: 'email',
			call_outcome: 'connected',
			occurred_at: minutesAgo(5)
		});
		expect(response.status).toBe(422);
	});

	it('refuses contact logged for later today, but allows a clock a minute fast', async () => {
		signedIn();
		const reply = { kind: 'contact', contact_direction: 'inbound', contact_channel: 'email' };
		const future = await add({ ...reply, occurred_at: minutesAgo(-60) });
		expect(future.status).toBe(422);
		expect((await future.json()).field_errors.occurred_at).toContain('not in the future');

		tableReturning({ data: { id: ENTRY_ID }, error: null });
		expect((await add({ ...reply, occurred_at: minutesAgo(-1) })).status).toBe(201);
	});

	it('explains a contact detail that was removed from the Lead meanwhile', async () => {
		signedIn();
		tableReturning({
			data: null,
			error: {
				code: '23503',
				message: 'violates foreign key constraint "platform_business_history_contact_method_fkey"'
			}
		});
		const response = await add({
			kind: 'contact',
			contact_direction: 'inbound',
			contact_channel: 'email',
			contact_method_id: METHOD_ID,
			occurred_at: minutesAgo(5)
		});
		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.contact_method_id).toContain(
			'no longer on this Lead'
		);
	});
});

describe('Correcting and removing history', () => {
	beforeEach(() => vi.clearAllMocks());

	const params = { id: LEAD_ID, entryId: ENTRY_ID };

	it('edits only an entry of the same kind on this Lead, and marks it edited', async () => {
		signedIn();
		const { calls } = tableReturning({ data: [{ id: ENTRY_ID }], error: null });
		const response = await EDIT_ENTRY(
			event(params, { method: 'PATCH', body: { kind: 'note', body: 'Fixed typo' } })
		);
		expect(response.status).toBe(200);
		expect(calls.update[0][0]).toMatchObject({ body: 'Fixed typo' });
		expect(calls.update[0][0]).not.toHaveProperty('kind');
		expect(calls.update[0][0]).toHaveProperty('edited_at');
		expect(calls.eq).toEqual([
			['id', ENTRY_ID],
			['relationship_id', LEAD_ID],
			['kind', 'note']
		]);
	});

	it('answers "no longer in the history" when nothing matched, such as a status change', async () => {
		signedIn();
		tableReturning({ data: [], error: null });
		const response = await EDIT_ENTRY(
			event(params, { method: 'PATCH', body: { kind: 'note', body: 'Rewrite history' } })
		);
		expect(response.status).toBe(404);
	});

	it('deletes only notes and logged contact', async () => {
		signedIn();
		const { calls } = tableReturning({ data: [{ id: ENTRY_ID }], error: null });
		const response = await DELETE_ENTRY(event(params, { method: 'DELETE' }));
		expect(response.status).toBe(200);
		expect(calls.in).toEqual([['kind', ['note', 'contact']]]);
	});
});

describe('Linking an Application', () => {
	beforeEach(() => vi.clearAllMocks());

	it('links an Application and records who did it', async () => {
		signedIn();
		const rpc = rpcReturning('linked');
		const response = await LINK_APPLICATION(
			event({ id: LEAD_ID }, { method: 'POST', body: { application_id: APPLICATION_ID } })
		);
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_lead_link_application', {
			actor_email: 'owner@example.com',
			target_id: LEAD_ID,
			target_application_id: APPLICATION_ID,
			target_link: true
		});
	});

	it('refuses an Application already linked to another business', async () => {
		signedIn();
		rpcReturning('linked_elsewhere');
		const response = await LINK_APPLICATION(
			event({ id: LEAD_ID }, { method: 'POST', body: { application_id: APPLICATION_ID } })
		);
		expect(response.status).toBe(409);
		expect((await response.json()).error).toContain('already linked to another business');
	});

	it('unlinks an Application', async () => {
		signedIn();
		const rpc = rpcReturning('unlinked');
		const response = await UNLINK_APPLICATION(
			event({ id: LEAD_ID, applicationId: APPLICATION_ID }, { method: 'DELETE' })
		);
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith(
			'owner_lead_link_application',
			expect.objectContaining({ target_link: false })
		);
	});
});
