import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as getInbox } from './threads/+server';
import { GET as getThread, PATCH as patchTopic } from './threads/[threadId]/+server';
import { POST as postReply } from './threads/[threadId]/messages/+server';
import { PATCH as patchSettings } from './settings/+server';
import { GET as getUnread } from './unread/+server';
import { POST as postRealtime } from './realtime/+server';
import { POST as postRead } from './threads/[threadId]/read/+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const THREAD_ID = '123e4567-e89b-12d3-a456-426614174000';
const CLIENT_MESSAGE_ID = '223e4567-e89b-12d3-a456-426614174000';

const threadRow = (id: string, senderKind = 'member', upliftLastReadAt: string | null = null) => ({
	id,
	topic: 'billing',
	started_by_user_id: 'user-1',
	last_message_at: '2026-10-01T10:00:00Z',
	uplift_last_read_at: upliftLastReadAt,
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
	const eqCalls: unknown[][] = [];
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
			eq: (...args: unknown[]) => {
				eqCalls.push(args);
				return chain;
			},
			order: () => chain,
			in: () => Promise.resolve({ data: list, error: null }),
			limit: () => Promise.resolve({ data: list, error: null }),
			maybeSingle: () => Promise.resolve({ data: single, error: null }),
			upsert,
			insert
		};
		return chain;
	});
	return { from, rpc, upsert, insert, eqCalls };
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
		['a topic change', () => patchTopic(event({ body: { topic: 'crm' } }))],
		[
			'a reply',
			() => postReply(event({ body: { body: 'Hi', client_message_id: CLIENT_MESSAGE_ID } }))
		],
		[
			'support settings',
			() => patchSettings(event({ body: { responder_name: 'Jafar', availability_note: '' } }))
		],
		['the unread count', () => getUnread(event())],
		['a live channel', () => postRealtime(event())],
		['a read mark', () => postRead(event({ body: { read_through: '2026-10-01T10:00:00Z' } }))]
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
			topic: 'billing',
			member_name: 'Sam Lee',
			last_message_sender_kind: 'member'
		});
		expect(body.has_more).toBe(false);
		expect(body.settings.responder_name).toBe('Jafar');
	});

	it('narrows the inbox to one topic when asked', async () => {
		const value = use(client({ threads: [threadRow('thread-1')] }));
		const response = await getInbox(event({ query: '?topic=billing' }));
		expect(response.status).toBe(200);
		expect(value.eqCalls).toContainEqual(['topic', 'billing']);
	});

	it('shows every topic when none is asked for', async () => {
		const value = use(client({ threads: [threadRow('thread-1')] }));
		await getInbox(event());
		expect(value.eqCalls).not.toContainEqual(['topic', expect.anything()]);
	});

	it('rejects a topic that is not listed, before the database', async () => {
		const response = await getInbox(event({ query: '?topic=gossip' }));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
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

	it('changes a chat’s topic as Uplift', async () => {
		const value = use(client({}));
		value.rpc.mockResolvedValue({ data: true, error: null });
		const response = await patchTopic(event({ body: { topic: 'crm' } }));
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ changed: true });
		expect(value.rpc).toHaveBeenCalledWith('set_support_thread_topic_by_uplift', {
			target_thread_id: THREAD_ID,
			new_topic: 'crm'
		});
	});

	it('rejects a topic that is not listed, or a chat that is not an id, before the database', async () => {
		expect((await patchTopic(event({ body: { topic: 'gossip' } }))).status).toBe(422);
		expect((await patchTopic(event({ body: { topic: 'crm' }, threadId: 'nope' }))).status).toBe(
			404
		);
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

describe('Support Inbox unread and live updates', () => {
	it('marks a thread unread only when the contractor wrote after Uplift last read it', async () => {
		use(
			client({
				threads: [
					threadRow('never-opened'),
					threadRow('read-before-message', 'member', '2026-10-01T09:00:00Z'),
					threadRow('read-after-message', 'member', '2026-10-01T10:00:00Z'),
					threadRow('uplift-replied', 'uplift', null)
				]
			})
		);
		const body = await (await getInbox(event())).json();
		expect(body.threads.map((thread: { unread: boolean }) => thread.unread)).toEqual([
			true,
			true,
			false,
			false
		]);
	});

	it('counts unread conversations for the Support menu item', async () => {
		const value = use(client({}));
		value.rpc.mockResolvedValue({ data: 2, error: null });
		const response = await getUnread(event());
		expect(await response.json()).toEqual({ unread: 2 });
		expect(value.rpc).toHaveBeenCalledWith('support_inbox_unread_count');
	});

	it("issues this owner session's live channel", async () => {
		const value = use(client({}));
		value.rpc.mockResolvedValue({ data: 'support-owner:' + 'a'.repeat(64), error: null });
		const response = await postRealtime(event());
		expect(await response.json()).toEqual({ topic: 'support-owner:' + 'a'.repeat(64) });
		expect(value.rpc).toHaveBeenCalledWith('issue_support_realtime_grant', {
			target_owner_session_id: 'session-id'
		});
	});

	it('marks a conversation read up to the given time', async () => {
		const value = use(client({}));
		value.rpc.mockResolvedValue({ data: null, error: null });
		const response = await postRead(event({ body: { read_through: '2026-10-01T10:00:00Z' } }));
		expect(response.status).toBe(204);
		expect(value.rpc).toHaveBeenCalledWith('mark_support_thread_read_by_uplift', {
			target_thread_id: THREAD_ID,
			read_through: '2026-10-01T10:00:00Z'
		});
	});

	it('rejects a read mark with no valid time, before the database', async () => {
		const response = await postRead(event({ body: { read_through: 'now' } }));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});
});
