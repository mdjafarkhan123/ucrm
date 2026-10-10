import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as getThread } from './thread/+server';
import { POST as postMessage } from './messages/+server';
import { GET as getChats, POST as startChat } from './threads/+server';
import { PATCH as changeTopic } from './threads/[threadId]/+server';
import { GET as getUnread } from './unread/+server';
import { POST as postRead } from './thread/read/+server';
import { POST as addPerson } from './threads/[threadId]/people/+server';
import { DELETE as removePerson } from './threads/[threadId]/people/[userId]/+server';
import { requireSupportMember } from '$lib/server/support/access';
import { unauthorized } from '$lib/server/api/errors';
import { checkRateLimit } from '$lib/server/security/rate-limit';

// Who counts as a support member is the database's answer (support_member_context, tested in
// access.spec.ts); these tests start from that answer.
vi.mock('$lib/server/setup/catalogue', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/setup/catalogue')>(
		'$lib/server/setup/catalogue'
	);
	const { SETUP_CATALOGUE_1 } = await import('$lib/setup/catalogue.fixture');
	return {
		...actual,
		readOrganizationSetupVersion: vi.fn(async () => SETUP_CATALOGUE_1),
		readOrganizationSetupCatalogue: vi.fn(async () => SETUP_CATALOGUE_1),
		readSetupSectionTitles: vi.fn(
			async () => new Map(SETUP_CATALOGUE_1.sections.map((section) => [section.key, section.title]))
		)
	};
});

vi.mock('$lib/server/support/access', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/support/access')>(
		'$lib/server/support/access'
	);
	return { ...actual, requireSupportMember: vi.fn() };
});
vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});

const mockedAccess = vi.mocked(requireSupportMember);
const mockedContext = {
	mockResolvedValue: (context: unknown) =>
		mockedAccess.mockResolvedValue(
			context ? { auth: context as never } : { response: unauthorized() }
		)
};
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

// The three reads a chat makes: the chat itself, the availability line, and the messages (newest first, as
// the database returns them).
function supabase(options: {
	thread?: { id: string; topic?: string; started_by_user_id?: string | null } | null;
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
			order: () => chain,
			limit: (count: number) => {
				limit(count);
				return Promise.resolve(result);
			},
			maybeSingle: () => Promise.resolve(result)
		};
		return chain;
	});
	const rpc = vi.fn(async (name: string): Promise<{ data: unknown; error: unknown }> =>
		name === 'support_teammate_names'
			? { data: options.profiles ?? [], error: null }
			: options.rpcError
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
	const open = (client: ReturnType<typeof supabase>, extra = '') =>
		getThread(event(client, { query: `?thread_id=${THREAD_ID}${extra}` }));

	it('refuses someone with no active organization', async () => {
		mockedContext.mockResolvedValue(null);
		const client = supabase({});
		const response = await open(client);
		expect(response.status).toBe(401);
		expect(client.from).not.toHaveBeenCalled();
	});

	it('answers any active team member, whatever their role', async () => {
		const response = await open(supabase({ thread: { id: THREAD_ID, topic: 'other' } }));
		expect(response.status).toBe(200);
	});

	it('names the chat the member asks for, and rejects a request that names none', async () => {
		const client = supabase({});
		const response = await getThread(event(client));
		expect(response.status).toBe(422);
		expect(client.from).not.toHaveBeenCalled();
	});

	it('returns the chat’s topic and the availability line', async () => {
		const client = supabase({
			thread: { id: THREAD_ID, topic: 'billing', started_by_user_id: 'user-1' },
			note: 'Mon–Fri. We reply within a day.'
		});
		const body = await (await open(client)).json();
		expect(body).toMatchObject({
			thread_id: THREAD_ID,
			topic: 'billing',
			messages: [],
			has_earlier: false,
			availability_note: 'Mon–Fri. We reply within a day.',
			started_by_name: null
		});
	});

	it('returns messages oldest first and never caches them publicly', async () => {
		const client = supabase({
			thread: { id: THREAD_ID, topic: 'other' },
			messages: [message('3', 'uplift'), message('2'), message('1')]
		});
		const response = await open(client);
		const body = await response.json();
		expect(body.messages.map((row: MessageRow) => row.id)).toEqual(['1', '2', '3']);
		expect(body.has_earlier).toBe(false);
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
	});

	it('reads one row past the page to say whether earlier messages exist', async () => {
		const client = supabase({
			thread: { id: THREAD_ID, topic: 'other' },
			messages: [message('3'), message('2'), message('1')]
		});
		const response = await open(client, '&limit=2');
		const body = await response.json();
		expect(client.limit).toHaveBeenCalledWith(3);
		expect(body.messages.map((row: MessageRow) => row.id)).toEqual(['2', '3']);
		expect(body.has_earlier).toBe(true);
	});

	it.each([
		['the person who started it', 'field', 'user-1', true],
		['an owner', 'owner', 'user-2', true],
		['an admin', 'admin', 'user-2', true],
		['someone else on the team', 'field', 'user-2', false]
	])('lets %s change the topic: %s', async (_name, role, starter, allowed) => {
		mockedContext.mockResolvedValue(member(role));
		const client = supabase({
			thread: { id: THREAD_ID, topic: 'other', started_by_user_id: starter },
			profiles: [{ id: 'user-2', full_name: 'Maria Lopez' }]
		});
		const body = await (await open(client)).json();
		expect(body.can_change_topic).toBe(allowed);
	});

	it('opens a teammate’s conversation the member can see, named after its starter', async () => {
		const client = supabase({
			thread: { id: THREAD_ID, topic: 'website', started_by_user_id: 'user-2' },
			profiles: [{ id: 'user-2', full_name: 'Maria Lopez' }],
			messages: [message('1')]
		});
		const response = await open(client);
		const body = await response.json();
		expect(response.status).toBe(200);
		expect(body.thread_id).toBe(THREAD_ID);
		expect(body.started_by_name).toBe('Maria Lopez');
	});

	it('answers 404 for a conversation row level security hides', async () => {
		const response = await open(supabase({ thread: null }));
		expect(response.status).toBe(404);
	});

	it('rejects a page size beyond the ceiling', async () => {
		const response = await open(supabase({}), '&limit=5000');
		expect(response.status).toBe(422);
	});
});

describe('POST /api/support/messages', () => {
	const reply = (text: string, extra: Record<string, unknown> = {}) => ({
		body: text,
		client_message_id: CLIENT_MESSAGE_ID,
		thread_id: THREAD_ID,
		...extra
	});

	it('refuses someone with no active organization', async () => {
		mockedContext.mockResolvedValue(null);
		const client = supabase({});
		const response = await postMessage(event(client, { body: reply('Hello') }));
		expect(response.status).toBe(401);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('sends the trimmed message into the named chat for the caller’s own organization', async () => {
		const client = supabase({});
		const response = await postMessage(event(client, { body: reply('  Hello  ') }));
		expect(response.status).toBe(201);
		expect(client.rpc).toHaveBeenCalledWith('send_support_message', {
			target_organization_id: 'org-1',
			target_thread_id: THREAD_ID,
			message_body: 'Hello',
			message_client_id: CLIENT_MESSAGE_ID,
			message_attachments: []
		});
		expect(mockedRateLimit).toHaveBeenCalledWith(
			client,
			expect.objectContaining({ bucketKey: 'support-send:user-1' })
		);
	});

	it('ignores an organization named in the body', async () => {
		const client = supabase({});
		await postMessage(event(client, { body: reply('Hello', { target_organization_id: 'org-2' }) }));
		expect(client.rpc).toHaveBeenCalledWith(
			'send_support_message',
			expect.objectContaining({ target_organization_id: 'org-1' })
		);
	});

	it.each([
		['an empty message', reply('   ')],
		['a message that is too long', reply('a'.repeat(4001))],
		['a message with no identifier', { body: 'Hello', thread_id: THREAD_ID }],
		['a message that names no chat', { body: 'Hello', client_message_id: CLIENT_MESSAGE_ID }]
	])('rejects %s before the database', async (_name, body) => {
		const client = supabase({});
		const response = await postMessage(event(client, { body }));
		expect(response.status).toBe(422);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('stops a flood of messages', async () => {
		mockedRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 30 });
		const client = supabase({});
		const response = await postMessage(event(client, { body: reply('Hello') }));
		expect(response.status).toBe(429);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('writes into the chat that is named', async () => {
		const client = supabase({});
		await postMessage(event(client, { body: reply('Hello') }));
		expect(client.rpc).toHaveBeenCalledWith(
			'send_support_message',
			expect.objectContaining({ target_thread_id: THREAD_ID })
		);
	});

	it('refuses a conversation the member cannot see', async () => {
		const client = supabase({ rpcError: { code: '42501', message: 'no' } });
		const response = await postMessage(event(client, { body: reply('Hello') }));
		expect(response.status).toBe(403);
		expect((await response.json()).error).toBe('That conversation is not one you can write in.');
	});
});

describe('GET /api/support/threads', () => {
	it('refuses someone with no active organization', async () => {
		mockedContext.mockResolvedValue(null);
		const client = supabase({});
		expect((await getChats(event(client))).status).toBe(401);
		expect(client.from).not.toHaveBeenCalled();
	});
});

describe('POST /api/support/threads', () => {
	const start = (extra: Record<string, unknown> = {}) => ({
		body: 'Hello',
		client_message_id: CLIENT_MESSAGE_ID,
		...extra
	});

	it('refuses someone with no active organization', async () => {
		mockedContext.mockResolvedValue(null);
		const client = supabase({});
		expect((await startChat(event(client, { body: start() }))).status).toBe(401);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('starts a chat in the caller’s own organization, topic Other when none is chosen', async () => {
		const client = supabase({});
		const response = await startChat(
			event(client, { body: start({ target_organization_id: 'org-2' }) })
		);
		expect(response.status).toBe(201);
		expect(client.rpc).toHaveBeenCalledWith('start_support_thread', {
			target_organization_id: 'org-1',
			thread_topic: 'other',
			message_body: 'Hello',
			message_client_id: CLIENT_MESSAGE_ID,
			message_attachments: []
		});
		expect(mockedRateLimit).toHaveBeenCalledWith(
			client,
			expect.objectContaining({ bucketKey: 'support-send:user-1' })
		);
	});

	it('starts a chat on the topic the member picked', async () => {
		const client = supabase({});
		await startChat(event(client, { body: start({ topic: 'google_profile' }) }));
		expect(client.rpc).toHaveBeenCalledWith(
			'start_support_thread',
			expect.objectContaining({ thread_topic: 'google_profile' })
		);
	});

	it('keeps the setup section an Ask Uplift chat was started from', async () => {
		const client = supabase({});
		await startChat(
			event(client, { body: start({ topic: 'setup', context_section: 'business' }) })
		);
		expect(client.rpc).toHaveBeenCalledWith(
			'start_support_thread',
			expect.objectContaining({ thread_topic: 'setup', thread_context_section: 'business' })
		);
	});

	it.each([
		['an empty message', start({ body: '   ' })],
		['a topic that is not listed', start({ topic: 'gossip' })],
		['a setup section that does not exist', start({ context_section: 'secret_plans' })],
		['a message with no identifier', { body: 'Hello' }]
	])('rejects %s before the database', async (_name, body) => {
		const client = supabase({});
		expect((await startChat(event(client, { body }))).status).toBe(422);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('stops a flood of new chats', async () => {
		mockedRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 30 });
		const client = supabase({});
		expect((await startChat(event(client, { body: start() }))).status).toBe(429);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('reports the database’s refusal of a non-member as no access', async () => {
		const client = supabase({ rpcError: { code: '42501', message: 'no' } });
		const response = await startChat(event(client, { body: start() }));
		expect(response.status).toBe(403);
	});
});

describe('PATCH /api/support/threads/[threadId]', () => {
	const params = { threadId: THREAD_ID };

	it('refuses someone with no active organization', async () => {
		mockedContext.mockResolvedValue(null);
		const client = supabase({});
		expect((await changeTopic(event(client, { body: { topic: 'crm' }, params }))).status).toBe(401);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('changes the topic through the database rule', async () => {
		const client = supabase({});
		client.rpc.mockResolvedValue({ data: true, error: null });
		const response = await changeTopic(event(client, { body: { topic: 'crm' }, params }));
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ changed: true });
		expect(client.rpc).toHaveBeenCalledWith('set_support_thread_topic', {
			target_thread_id: THREAD_ID,
			new_topic: 'crm'
		});
	});

	it.each([
		['a topic that is not listed', { topic: 'gossip' }, THREAD_ID, 422],
		['a chat that is not an id', { topic: 'crm' }, 'chat-1', 404]
	])('rejects %s before the database', async (_name, body, threadId, status) => {
		const client = supabase({});
		const response = await changeTopic(event(client, { body, params: { threadId } }));
		expect(response.status).toBe(status);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('passes on the database’s refusal of someone who may not change it', async () => {
		const client = supabase({
			rpcError: { code: '42501', message: 'Only the person who started this chat…' }
		});
		const response = await changeTopic(event(client, { body: { topic: 'crm' }, params }));
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
