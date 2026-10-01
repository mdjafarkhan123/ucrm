import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as getThread } from './thread/+server';
import { POST as postMessage } from './messages/+server';
import { GET as getUnread } from './unread/+server';
import { POST as postRead } from './thread/read/+server';
import { POST as addPerson } from './threads/[threadId]/people/+server';
import { DELETE as removePerson } from './threads/[threadId]/people/[userId]/+server';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/auth/organization', () => ({ getOrganizationContext: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});

const mockedContext = vi.mocked(getOrganizationContext);
const mockedRateLimit = vi.mocked(checkRateLimit);

const CLIENT_MESSAGE_ID = '123e4567-e89b-12d3-a456-426614174000';
const THREAD_ID = '223e4567-e89b-12d3-a456-426614174000';
const TEAMMATE_ID = '423e4567-e89b-12d3-a456-426614174000';

type MessageRow = {
	id: string;
	sender_kind: string;
	sender_name: string;
	body: string;
	created_at: string;
};

// The three reads a thread makes: the member's thread, the availability line, and the messages (newest
// first, as the database returns them).
function supabase(options: {
	thread?: { id: string; started_by_user_id?: string | null } | null;
	teamCount?: number;
	profiles?: { id: string; full_name: string }[];
	note?: string;
	messages?: MessageRow[];
	rpcError?: { code: string; message: string } | null;
}) {
	const limit = vi.fn();
	const rows: Record<string, unknown> = {
		support_threads: options.thread ?? null,
		platform_support_settings: { availability_note: options.note ?? '' },
		support_messages: options.messages ?? [],
		profiles: options.profiles ?? []
	};
	const from = vi.fn((table: string) => {
		const result = { data: rows[table], error: null };
		const chain = {
			select: () => chain,
			eq: () => chain,
			in: () => Promise.resolve(result),
			// The "Team chats" count is the only read that ends on this filter.
			or: () => Promise.resolve({ count: options.teamCount ?? 0, error: null }),
			order: () => chain,
			limit: (count: number) => {
				limit(count);
				return Promise.resolve(result);
			},
			maybeSingle: () => Promise.resolve(result)
		};
		return chain;
	});
	const rpc = vi.fn().mockResolvedValue(
		options.rpcError
			? { data: null, error: options.rpcError }
			: {
					data: {
						id: 'message-1',
						thread_id: 'thread-1',
						sender_kind: 'member',
						sender_name: 'Sam Lee',
						body: 'Hello',
						created_at: '2026-10-01T10:00:00Z'
					},
					error: null
				}
	);
	return { from, rpc, limit };
}

function event(
	client: ReturnType<typeof supabase>,
	options: { body?: unknown; query?: string; params?: Record<string, string> } = {}
) {
	return {
		locals: { supabase: client },
		params: options.params ?? {},
		url: new URL(`http://localhost/api/support/thread${options.query ?? ''}`),
		request: new Request('http://localhost/api/support/messages', {
			method: 'POST',
			body: options.body === undefined ? undefined : JSON.stringify(options.body)
		})
	} as never;
}

function member(role = 'field') {
	return {
		organization: { id: 'org-1', name: 'Bright Spark Electrical', slug: 'bright-spark', role },
		user: { id: 'user-1', email: 'sam@example.com' }
	} as never;
}

const message = (id: string, sender_kind = 'member'): MessageRow => ({
	id,
	sender_kind,
	sender_name: sender_kind === 'uplift' ? 'Jafar' : 'Sam Lee',
	body: `Message ${id}`,
	created_at: '2026-10-01T10:00:00Z'
});

beforeEach(() => {
	vi.clearAllMocks();
	mockedContext.mockResolvedValue(member());
	mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
});

describe('GET /api/support/thread', () => {
	it('refuses someone with no active organization', async () => {
		mockedContext.mockResolvedValue(null);
		const client = supabase({});
		const response = await getThread(event(client));
		expect(response.status).toBe(401);
		expect(client.from).not.toHaveBeenCalled();
	});

	it('answers any active team member, whatever their role', async () => {
		const response = await getThread(event(supabase({})));
		expect(response.status).toBe(200);
	});

	it('returns an empty conversation, with the availability line, before the first message', async () => {
		const client = supabase({ note: 'Mon–Fri. We reply within a day.' });
		const response = await getThread(event(client));
		expect(await response.json()).toEqual({
			thread_id: null,
			messages: [],
			has_earlier: false,
			availability_note: 'Mon–Fri. We reply within a day.',
			started_by_name: null,
			team_thread_count: 0
		});
		expect(client.from).not.toHaveBeenCalledWith('support_messages');
	});

	it('returns messages oldest first and never caches them publicly', async () => {
		const client = supabase({
			thread: { id: 'thread-1' },
			messages: [message('3', 'uplift'), message('2'), message('1')]
		});
		const response = await getThread(event(client));
		const body = await response.json();
		expect(body.messages.map((row: MessageRow) => row.id)).toEqual(['1', '2', '3']);
		expect(body.has_earlier).toBe(false);
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
	});

	it('reads one row past the page to say whether earlier messages exist', async () => {
		const client = supabase({
			thread: { id: 'thread-1' },
			messages: [message('3'), message('2'), message('1')]
		});
		const response = await getThread(event(client, { query: '?limit=2' }));
		const body = await response.json();
		expect(client.limit).toHaveBeenCalledWith(3);
		expect(body.messages.map((row: MessageRow) => row.id)).toEqual(['2', '3']);
		expect(body.has_earlier).toBe(true);
	});

	it('counts the team conversations the member may also see', async () => {
		const client = supabase({
			thread: { id: 'thread-1', started_by_user_id: 'user-1' },
			teamCount: 3
		});
		const body = await (await getThread(event(client))).json();
		expect(body.team_thread_count).toBe(3);
		expect(body.started_by_name).toBeNull();
	});

	it('opens a teammate’s conversation the member can see, named after its starter', async () => {
		const client = supabase({
			thread: { id: THREAD_ID, started_by_user_id: 'user-2' },
			profiles: [{ id: 'user-2', full_name: 'Maria Lopez' }],
			messages: [message('1')]
		});
		const response = await getThread(event(client, { query: `?thread_id=${THREAD_ID}` }));
		const body = await response.json();
		expect(response.status).toBe(200);
		expect(body.thread_id).toBe(THREAD_ID);
		expect(body.started_by_name).toBe('Maria Lopez');
	});

	it('answers 404 for a conversation row level security hides', async () => {
		const client = supabase({ thread: null });
		const response = await getThread(event(client, { query: `?thread_id=${THREAD_ID}` }));
		expect(response.status).toBe(404);
		expect(client.from).not.toHaveBeenCalledWith('support_messages');
	});

	it('rejects a page size beyond the ceiling', async () => {
		const response = await getThread(event(supabase({}), { query: '?limit=5000' }));
		expect(response.status).toBe(422);
	});
});

describe('POST /api/support/messages', () => {
	it('refuses someone with no active organization', async () => {
		mockedContext.mockResolvedValue(null);
		const client = supabase({});
		const response = await postMessage(
			event(client, { body: { body: 'Hello', client_message_id: CLIENT_MESSAGE_ID } })
		);
		expect(response.status).toBe(401);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('sends the trimmed message for the caller’s own organization', async () => {
		const client = supabase({});
		const response = await postMessage(
			event(client, { body: { body: '  Hello  ', client_message_id: CLIENT_MESSAGE_ID } })
		);
		expect(response.status).toBe(201);
		expect(client.rpc).toHaveBeenCalledWith('send_support_message', {
			target_organization_id: 'org-1',
			message_body: 'Hello',
			message_client_id: CLIENT_MESSAGE_ID
		});
		expect(mockedRateLimit).toHaveBeenCalledWith(
			client,
			expect.objectContaining({ bucketKey: 'support-send:user-1' })
		);
	});

	it('ignores an organization named in the body', async () => {
		const client = supabase({});
		await postMessage(
			event(client, {
				body: {
					body: 'Hello',
					client_message_id: CLIENT_MESSAGE_ID,
					target_organization_id: 'org-2'
				}
			})
		);
		expect(client.rpc).toHaveBeenCalledWith(
			'send_support_message',
			expect.objectContaining({ target_organization_id: 'org-1' })
		);
	});

	it.each([
		['an empty message', { body: '   ', client_message_id: CLIENT_MESSAGE_ID }],
		[
			'a message that is too long',
			{ body: 'a'.repeat(4001), client_message_id: CLIENT_MESSAGE_ID }
		],
		['a message with no identifier', { body: 'Hello' }]
	])('rejects %s before the database', async (_name, body) => {
		const client = supabase({});
		const response = await postMessage(event(client, { body }));
		expect(response.status).toBe(422);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('stops a flood of messages', async () => {
		mockedRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 30 });
		const client = supabase({});
		const response = await postMessage(
			event(client, { body: { body: 'Hello', client_message_id: CLIENT_MESSAGE_ID } })
		);
		expect(response.status).toBe(429);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('writes into a teammate’s conversation when one is named', async () => {
		const client = supabase({});
		await postMessage(
			event(client, {
				body: { body: 'Hello', client_message_id: CLIENT_MESSAGE_ID, thread_id: THREAD_ID }
			})
		);
		expect(client.rpc).toHaveBeenCalledWith(
			'send_support_message',
			expect.objectContaining({ target_thread_id: THREAD_ID })
		);
	});

	it('refuses a conversation the member cannot see', async () => {
		const client = supabase({ rpcError: { code: '42501', message: 'no' } });
		const response = await postMessage(
			event(client, {
				body: { body: 'Hello', client_message_id: CLIENT_MESSAGE_ID, thread_id: THREAD_ID }
			})
		);
		expect(response.status).toBe(403);
		expect((await response.json()).error).toBe('That conversation is not one you can write in.');
	});

	it('reports the database’s refusal of a non-member as no access', async () => {
		const client = supabase({ rpcError: { code: '42501', message: 'no' } });
		const response = await postMessage(
			event(client, { body: { body: 'Hello', client_message_id: CLIENT_MESSAGE_ID } })
		);
		expect(response.status).toBe(403);
	});
});

describe('GET /api/support/unread', () => {
	it('refuses someone with no active organization', async () => {
		mockedContext.mockResolvedValue(null);
		const client = supabase({});
		expect((await getUnread(event(client))).status).toBe(401);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it("counts the signed-in member's unread messages in their own organization", async () => {
		const client = supabase({});
		client.rpc.mockResolvedValue({ data: 3, error: null });
		const response = await getUnread(event(client));
		expect(await response.json()).toEqual({ unread: 3 });
		expect(client.rpc).toHaveBeenCalledWith('support_unread_count', {
			target_organization_id: 'org-1'
		});
	});
});

describe('POST /api/support/thread/read', () => {
	const READ_THROUGH = '2026-10-01T10:00:00.123456+00:00';

	it('refuses someone with no active organization', async () => {
		mockedContext.mockResolvedValue(null);
		const client = supabase({});
		const response = await postRead(
			event(client, { body: { thread_id: THREAD_ID, read_through: READ_THROUGH } })
		);
		expect(response.status).toBe(401);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it.each([
		['a missing time', { thread_id: THREAD_ID }],
		['a time that is not a time', { thread_id: THREAD_ID, read_through: 'yesterday' }],
		['a thread id that is not an id', { thread_id: 'thread-1', read_through: READ_THROUGH }]
	])('rejects %s before the database', async (_name, body) => {
		const client = supabase({});
		expect((await postRead(event(client, { body }))).status).toBe(422);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('marks the thread read up to the newest message the screen showed', async () => {
		const client = supabase({});
		client.rpc.mockResolvedValue({ data: null, error: null });
		const response = await postRead(
			event(client, { body: { thread_id: THREAD_ID, read_through: READ_THROUGH } })
		);
		expect(response.status).toBe(204);
		expect(client.rpc).toHaveBeenCalledWith('mark_support_thread_read', {
			target_thread_id: THREAD_ID,
			read_through: READ_THROUGH
		});
	});

	it("answers 403 for someone else's thread", async () => {
		const client = supabase({ rpcError: { code: '42501', message: 'no' } });
		const response = await postRead(
			event(client, { body: { thread_id: THREAD_ID, read_through: READ_THROUGH } })
		);
		expect(response.status).toBe(403);
	});
});

describe('adding and removing teammates', () => {
	it('refuses someone with no active organization', async () => {
		mockedContext.mockResolvedValue(null);
		const client = supabase({});
		const response = await addPerson(
			event(client, { body: { user_id: TEAMMATE_ID }, params: { threadId: THREAD_ID } })
		);
		expect(response.status).toBe(401);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('rejects a teammate that is not an id before the database', async () => {
		const client = supabase({});
		const response = await addPerson(
			event(client, { body: { user_id: 'maria' }, params: { threadId: THREAD_ID } })
		);
		expect(response.status).toBe(422);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('adds a teammate through the database rule', async () => {
		const client = supabase({});
		client.rpc.mockResolvedValue({ data: true, error: null });
		const response = await addPerson(
			event(client, { body: { user_id: TEAMMATE_ID }, params: { threadId: THREAD_ID } })
		);
		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith('set_support_thread_participant', {
			target_thread_id: THREAD_ID,
			target_user_id: TEAMMATE_ID,
			adding: true
		});
	});

	it('passes on the database’s refusal of someone who may not change the list', async () => {
		const client = supabase({
			rpcError: { code: '42501', message: 'Only the person who started this conversation…' }
		});
		const response = await addPerson(
			event(client, { body: { user_id: TEAMMATE_ID }, params: { threadId: THREAD_ID } })
		);
		expect(response.status).toBe(403);
	});

	it('removes a teammate named in the path', async () => {
		const client = supabase({});
		client.rpc.mockResolvedValue({ data: true, error: null });
		const response = await removePerson(
			event(client, { params: { threadId: THREAD_ID, userId: TEAMMATE_ID } })
		);
		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith('set_support_thread_participant', {
			target_thread_id: THREAD_ID,
			target_user_id: TEAMMATE_ID,
			adding: false
		});
	});
});
