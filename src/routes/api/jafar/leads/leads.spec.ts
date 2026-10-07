import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { POST as CHECK_DUPLICATES } from './duplicates/+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function rpcReturning(data: unknown) {
	const rpc = vi.fn().mockResolvedValue({ data, error: null });
	mockedClient.mockReturnValue({ rpc } as unknown as ReturnType<typeof getOwnerSupabaseClient>);
	return rpc;
}

function getEvent(url = 'http://localhost/api/jafar/leads') {
	return { url: new URL(url), params: {}, cookies: {} } as unknown as Parameters<typeof GET>[0];
}

// Shaped as any route's event, so the same helper serves both the Leads and the duplicate-check endpoints.
function postEvent(body: unknown, url = 'http://localhost/api/jafar/leads'): never {
	return {
		url: new URL(url),
		params: {},
		cookies: {},
		request: new Request(url, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		})
	} as never;
}

const listResult = {
	leads: [],
	next_cursor: null,
	totals: { all: 0, matching: 0, statuses: {}, countries: [], sources: {} }
};

const smithPlumbing = {
	business_name: 'Smith Plumbing',
	country_code: 'gb',
	trade: 'Plumbing',
	source: 'own_website',
	website: 'https://www.smithplumbing.co.uk',
	contact_methods: [
		{ kind: 'email', value: 'info@smithplumbing.co.uk', found_at: 'Contact page of their website' }
	]
};

describe('Leads list GET', () => {
	beforeEach(() => vi.clearAllMocks());

	it('refuses a caller without the owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const response = await GET(getEvent());
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('refuses a status the list does not know', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const response = await GET(getEvent('http://localhost/api/jafar/leads?status=approved'));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('asks for every filter, newest first, when none is set', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const rpc = rpcReturning(listResult);
		const response = await GET(getEvent());
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_lead_list', {
			search_term: undefined,
			status_filter: undefined,
			country_filter: undefined,
			source_filter: undefined,
			sort_order: 'newest',
			cursor_created_at: undefined,
			cursor_due_on: undefined,
			cursor_id: undefined,
			page_size: 50
		});
	});

	it('passes status and country filters through, countries upper-cased and each once', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const rpc = rpcReturning(listResult);
		await GET(getEvent('http://localhost/api/jafar/leads?status=new,later&country=gb,US,GB'));
		expect(rpc).toHaveBeenCalledWith(
			'owner_lead_list',
			expect.objectContaining({ status_filter: ['new', 'later'], country_filter: ['GB', 'US'] })
		);
	});

	it('turns the next page cursor into an opaque string and back', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const cursor = { created_at: '2026-10-07T03:00:00Z', due_on: '0001-01-01', id: 'lead-1' };
		rpcReturning({ ...listResult, next_cursor: cursor });
		const first = await (await GET(getEvent())).json();
		expect(typeof first.next_cursor).toBe('string');

		const rpc = rpcReturning(listResult);
		await GET(
			getEvent(`http://localhost/api/jafar/leads?cursor=${encodeURIComponent(first.next_cursor)}`)
		);
		expect(rpc).toHaveBeenCalledWith(
			'owner_lead_list',
			expect.objectContaining({
				cursor_created_at: cursor.created_at,
				cursor_due_on: cursor.due_on,
				cursor_id: cursor.id
			})
		);
	});

	it('refuses a cursor it did not make', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const response = await GET(getEvent('http://localhost/api/jafar/leads?cursor=not-a-cursor'));
		expect(response.status).toBe(422);
	});
});

describe('Adding a Lead POST', () => {
	beforeEach(() => vi.clearAllMocks());

	it('refuses a caller without the owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const response = await POST(postEvent(smithPlumbing));
		expect(response.status).toBe(401);
	});

	it('saves the Lead as the signed-in owner, with its contact details in order', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const rpc = rpcReturning('lead-1');
		const response = await POST(postEvent(smithPlumbing));
		expect(response.status).toBe(201);
		expect(await response.json()).toEqual({ id: 'lead-1' });
		expect(rpc).toHaveBeenCalledWith(
			'owner_create_lead',
			expect.objectContaining({
				actor_email: 'owner@example.com',
				target_business_name: 'Smith Plumbing',
				target_country_code: 'GB',
				target_lead_status: 'new',
				target_contact_methods: smithPlumbing.contact_methods,
				target_next_action: undefined
			})
		);
	});

	it('names each missing required field', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const response = await POST(postEvent({ business_name: ' ' }));
		expect(response.status).toBe(422);
		const body = await response.json();
		expect(Object.keys(body.field_errors)).toEqual(
			expect.arrayContaining(['business_name', 'country_code', 'trade', 'source'])
		);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('needs a due date with a next action, and a next action with a due date', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const withoutDate = await POST(postEvent({ ...smithPlumbing, next_action: 'Email the owner' }));
		expect((await withoutDate.json()).field_errors).toHaveProperty('next_action_due_on');
		const withoutAction = await POST(
			postEvent({ ...smithPlumbing, next_action_due_on: '2026-10-10' })
		);
		expect((await withoutAction.json()).field_errors).toHaveProperty('next_action');
	});

	it('marks the exact contact row that is wrong', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const response = await POST(
			postEvent({
				...smithPlumbing,
				contact_methods: [
					smithPlumbing.contact_methods[0],
					{ kind: 'phone', value: '123', found_at: 'Google Business Profile' },
					{ kind: 'email', value: 'office@smithplumbing.co.uk', found_at: ' ' }
				]
			})
		);
		const errors = (await response.json()).field_errors;
		expect(errors).toHaveProperty(['contact_methods.1.value']);
		expect(errors).toHaveProperty(['contact_methods.2.found_at']);
		expect(errors).not.toHaveProperty(['contact_methods.0.value']);
	});
});

describe('Possible duplicate check POST', () => {
	beforeEach(() => vi.clearAllMocks());

	it('refuses a caller without the owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const response = await CHECK_DUPLICATES(
			postEvent({ website: 'smithplumbing.co.uk' }, 'http://localhost/api/jafar/leads/duplicates')
		);
		expect(response.status).toBe(401);
	});

	it('answers with nothing, without asking the database, when there is nothing to compare', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const response = await CHECK_DUPLICATES(
			postEvent({ business_name: '', emails: [''] }, 'http://localhost/api/jafar/leads/duplicates')
		);
		expect(await response.json()).toEqual({ duplicates: [] });
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns what the database found for the same website', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const match = {
			kind: 'lead',
			id: 'lead-1',
			name: 'Smith Plumbing',
			country_code: 'GB',
			matched_on: ['website']
		};
		const rpc = rpcReturning([match]);
		const response = await CHECK_DUPLICATES(
			postEvent(
				{ website: 'https://smithplumbing.co.uk/about', country_code: 'gb' },
				'http://localhost/api/jafar/leads/duplicates'
			)
		);
		expect(await response.json()).toEqual({ duplicates: [match] });
		expect(rpc).toHaveBeenCalledWith(
			'owner_lead_possible_duplicates',
			expect.objectContaining({
				website: 'https://smithplumbing.co.uk/about',
				country_code: 'GB',
				emails: [],
				phones: []
			})
		);
	});
});
