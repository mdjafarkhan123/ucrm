import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as getInbox } from './threads/+server';
import { GET as getThread } from './threads/[threadId]/+server';
import { POST as postReply } from './threads/[threadId]/messages/+server';
import { PATCH as patchSettings } from './settings/+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const THREAD_ID = '123e4567-e89b-12d3-a456-426614174000';
const CLIENT_MESSAGE_ID = '223e4567-e89b-12d3-a456-426614174000';

const threadRow = (id: string, senderKind = 'member') => ({
	id,
	started_by_user_id: 'user-1',
	last_message_at: '2026-10-01T10:00:00Z',
	last_message_preview: 'Hello',
	last_message_sender_kind: senderKind,
	organizations: { id: 'org-1', name: 'Bright Spark Electrical' }
});

function client(options: {
	threads?: unknown[];
	thread?: unknown;
	messages?: unknown[];
	settings?: { responder_name: string; availability_note: string };
	rpcError?: { code: string; message: string } | null;
}) {
	const upsert = vi.fn().mockResolvedValue({ error: null });
	const insert = vi.fn().mockResolvedValue({ error: null });
	const rpc = vi
		.fn()
		.mockResolvedValue(
			options.rpcError
				? { data: null, error: options.rpcError }
				: { data: { id: 'message-1', sender_kind: 'uplift', sender_name: 'Jafar' }, error: null }
		);
	const from = vi.fn((table: string) => {
		const list =
			table === 'support_threads'
				? (options.threads ?? [])
				: table === 'support_messages'
					? (options.messages ?? [])
					: table === 'profiles'
						? [{ id: 'user-1', full_name: 'Sam Lee' }]
						: [];
		const single =
			table === 'support_threads'
				? (options.thread ?? null)
				: (options.settings ?? { responder_name: '', availability_note: '' });
		const chain = {
			select: () => chain,
			eq: () => chain,
			order: () => chain,
			in: () => Promise.resolve({ data: list, error: null }),
			limit: () => Promise.resolve({ data: list, error: null }),
			maybeSingle: () => Promise.resolve({ data: single, error: null }),
			upsert,
			insert
		};
		return chain;
	});
	return { from, rpc, upsert, insert };
}

function event(options: { body?: unknown; threadId?: string; query?: string } = {}) {
	return {
		params: { threadId: options.threadId ?? THREAD_ID },
		url: new URL(`http://localhost/api/jafar/support/threads${options.query ?? ''}`),
		request: new Request('http://localhost/api/jafar/support', {
			method: 'POST',
			body: options.body === undefined ? undefined : JSON.stringify(options.body)
		}),
		cookies: {}
	} as never;
}

function use(value: ReturnType<typeof client>) {
	mockedClient.mockReturnValue(value as never);
	return value;
}

beforeEach(() => {
	vi.clearAllMocks();
	mockedOwnerSession.mockResolvedValue({ email: 'owner@example.com', sessionId: 'session-id' });
});

describe('Support Inbox API boundary', () => {
	it.each([
		['the inbox', () => getInbox(event())],
		['a conversation', () => getThread(event())],
		[
			'a reply',
			() => postReply(event({ body: { body: 'Hi', client_message_id: CLIENT_MESSAGE_ID } }))
		],
		[
			'support settings',
			() => patchSettings(event({ body: { responder_name: 'Jafar', availability_note: '' } }))
		]
	])('refuses %s without the platform owner session', async (_name, call) => {
		mockedOwnerSession.mockResolvedValue(null);
		const response = await call();
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('lists threads with their organization, member and who wrote last', async () => {
		use(
			client({
				threads: [threadRow('thread-1'), threadRow('thread-2', 'uplift')],
				settings: { responder_name: 'Jafar', availability_note: '' }
			})
		);
		const body = await (await getInbox(event())).json();
		expect(body.threads).toHaveLength(2);
		expect(body.threads[0]).toMatchObject({
			id: 'thread-1',
			organization: { id: 'org-1', name: 'Bright Spark Electrical' },
			member_name: 'Sam Lee',
			last_message_sender_kind: 'member'
		});
		expect(body.has_more).toBe(false);
		expect(body.settings.responder_name).toBe('Jafar');
	});

	it('answers 404 for a conversation that does not exist', async () => {
		use(client({ thread: null }));
		const response = await getThread(event());
		expect(response.status).toBe(404);
	});

	it('answers 404 for an id that is not an id, without asking the database', async () => {
		const response = await getThread(event({ threadId: 'not-a-uuid' }));
		expect(response.status).toBe(404);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('replies as the signed-in owner and never takes the display name from the request', async () => {
		const value = use(client({}));
		const response = await postReply(
			event({
				body: { body: ' On it. ', client_message_id: CLIENT_MESSAGE_ID, sender_name: 'Somebody' }
			})
		);
		expect(response.status).toBe(201);
		expect(value.rpc).toHaveBeenCalledWith('reply_to_support_thread', {
			target_thread_id: THREAD_ID,
			actor_email: 'owner@example.com',
			message_body: 'On it.',
			message_client_id: CLIENT_MESSAGE_ID
		});
	});

	it('passes on the database’s sentence when the responder name is missing', async () => {
		use(
			client({
				rpcError: {
					code: '23514',
					message: 'Add the name clients see on your replies before sending one.'
				}
			})
		);
		const response = await postReply(
			event({ body: { body: 'On it.', client_message_id: CLIENT_MESSAGE_ID } })
		);
		expect(response.status).toBe(422);
		expect((await response.json()).error).toContain('Add the name');
	});

	it('rejects an empty reply before the database', async () => {
		const response = await postReply(
			event({ body: { body: '  ', client_message_id: CLIENT_MESSAGE_ID } })
		);
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('saves support settings and records who changed them', async () => {
		const value = use(client({ settings: { responder_name: '', availability_note: '' } }));
		const response = await patchSettings(
			event({ body: { responder_name: ' Jafar ', availability_note: 'Mon–Fri, 9 to 5.' } })
		);
		expect(response.status).toBe(200);
		expect(value.upsert).toHaveBeenCalledWith(
			{ id: true, responder_name: 'Jafar', availability_note: 'Mon–Fri, 9 to 5.' },
			{ onConflict: 'id' }
		);
		expect(value.insert).toHaveBeenCalledWith(
			expect.objectContaining({
				actor_owner_email: 'owner@example.com',
				event_type: 'support_settings.updated'
			})
		);
	});

	it('refuses support settings with no responder name', async () => {
		const value = use(client({}));
		const response = await patchSettings(
			event({ body: { responder_name: ' ', availability_note: '' } })
		);
		expect(response.status).toBe(422);
		expect(value.upsert).not.toHaveBeenCalled();
	});
});
