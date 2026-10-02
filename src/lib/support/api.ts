import { httpError } from '$lib/http-error';

// The Uplift Support Messenger: a team member writes to Uplift, Uplift answers from the /jafar Support Inbox.
// Separate from the contractor's own customer inbox in every way — its own tables, routes and cache keys
// (docs/client-onboarding-delivery-behavior-contract.md §7).

/** `system` and `ai` are reserved for later senders; nothing writes them yet. */
export type SupportSenderKind = 'member' | 'uplift' | 'system' | 'ai';

// Each question is its own chat with one topic (D4a; Intercom's messenger, a Zendesk-style "type" field).
// Picking one is optional: a chat starts as Other.
export const SUPPORT_TOPICS = [
	{ value: 'setup', label: 'Setup' },
	{ value: 'website', label: 'Website' },
	{ value: 'google_profile', label: 'Google Profile' },
	{ value: 'crm', label: 'CRM' },
	{ value: 'billing', label: 'Billing' },
	{ value: 'other', label: 'Other' }
] as const;

export type SupportTopic = (typeof SUPPORT_TOPICS)[number]['value'];

export const SUPPORT_TOPIC_VALUES = SUPPORT_TOPICS.map((topic) => topic.value) as [
	SupportTopic,
	...SupportTopic[]
];

export function supportTopicLabel(topic: SupportTopic): string {
	return SUPPORT_TOPICS.find((item) => item.value === topic)?.label ?? 'Other';
}

export type SupportMessage = {
	id: string;
	sender_kind: SupportSenderKind;
	/** The team member who wrote it. Null for Uplift, system lines, and a member whose account is gone. */
	sender_user_id: string | null;
	sender_name: string;
	body: string;
	created_at: string;
};

export type SupportThread = {
	thread_id: string;
	topic: SupportTopic;
	/** The viewer may change the topic: the chat's starter, or an owner or admin. */
	can_change_topic: boolean;
	/** Oldest first. */
	messages: SupportMessage[];
	has_earlier: boolean;
	/** Uplift's own words for its hours and usual reply time. Empty when Uplift has not written one. */
	availability_note: string;
	/** Whose chat it is. Null for the member's own. */
	started_by_name: string | null;
};

// Who sees what (D3, Zendesk's "My / CC'd / Organization requests"): a member sees the chats they started
// and ones they were added to; owners and admins see every chat in their organization.

/** One row in the messenger's chat lists. */
export type SupportChatRow = {
	id: string;
	topic: SupportTopic;
	/** Who started it. For the member's own chats this is their own name. */
	started_by_name: string;
	last_message_at: string;
	last_message_preview: string;
	last_message_sender_kind: SupportSenderKind;
	/** Something arrived since the member last looked. */
	unread: boolean;
	/** The member was added to it, rather than seeing it as an owner or admin. */
	added: boolean;
};

export type SupportChats = {
	/** The member's own chats, newest first. */
	mine: SupportChatRow[];
	/** Someone else's chats the member may see: added to, or every one for an owner or admin. */
	team: SupportChatRow[];
	/** Uplift's own words for its hours and usual reply time. Empty when Uplift has not written one. */
	availability_note: string;
};

export type SupportPerson = {
	user_id: string;
	name: string;
	/** Started the conversation. Always in it, never removable. */
	started: boolean;
	/** Still an active member of the team. */
	active: boolean;
};

export type SupportPeople = {
	people: SupportPerson[];
	/** Active teammates not in the conversation yet. */
	addable: { user_id: string; name: string }[];
	/** The viewer may add and remove people: the starter, an owner or admin, or Uplift. */
	can_manage: boolean;
};

export const SUPPORT_MESSAGE_MAX_LENGTH = 4000;
export const SUPPORT_PAGE_SIZE = 50;
export const SUPPORT_MAX_LOADED = 500;

export type SupportUnread = { unread: number };

// The user id is part of the key: the query client outlives sign-out, and chats belong to one person.
// Every chat, list and people panel sits under this prefix, so one live ping refreshes them all.
export const supportKey = (userId: string | null) => ['support', 'chats', userId] as const;
export const supportChatsKey = (userId: string | null) => [...supportKey(userId), 'list'] as const;
export const supportThreadKey = (userId: string | null, threadId: string) =>
	[...supportKey(userId), 'thread', threadId] as const;
export const supportThreadPageKey = (userId: string | null, threadId: string, limit: number) =>
	[...supportThreadKey(userId, threadId), limit] as const;
export const supportPeopleKey = (userId: string | null, threadId: string | null) =>
	[...supportKey(userId), 'people', threadId] as const;

export const supportUnreadKey = (userId: string | null) => ['support', 'unread', userId] as const;

export async function fetchSupportThread(threadId: string, limit: number): Promise<SupportThread> {
	const response = await fetch(`/api/support/thread?thread_id=${threadId}&limit=${limit}`);
	if (!response.ok) throw httpError(response, 'This conversation could not be loaded.');
	return response.json();
}

export async function fetchSupportChats(): Promise<SupportChats> {
	const response = await fetch('/api/support/threads');
	if (!response.ok) throw httpError(response, 'Your chats could not be loaded.');
	return response.json();
}

export async function fetchSupportPeople(threadId: string): Promise<SupportPeople> {
	const response = await fetch(`/api/support/threads/${threadId}/people`);
	if (!response.ok)
		throw httpError(response, 'The people in this conversation could not be loaded.');
	return response.json();
}

// Adding posts the teammate; removing names them in the path. `base` is the conversation's people route.
async function changePeople(base: string, userId: string, adding: boolean): Promise<void> {
	const response = await fetch(
		adding ? base : `${base}/${userId}`,
		adding
			? {
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({ user_id: userId })
				}
			: { method: 'DELETE' }
	);
	if (!response.ok)
		throw await failure(
			response,
			adding ? 'That teammate could not be added.' : 'That teammate could not be removed.'
		);
}

export const changeSupportPeople = (threadId: string, userId: string, adding: boolean) =>
	changePeople(`/api/support/threads/${threadId}/people`, userId, adding);

export async function fetchSupportUnread(): Promise<SupportUnread> {
	const response = await fetch('/api/support/unread');
	if (!response.ok) throw httpError(response, 'Unread messages could not be counted.');
	return response.json();
}

/** The member's screen showed a chat up to `readThrough`, the newest message's time. */
export async function markSupportThreadRead(threadId: string, readThrough: string) {
	const response = await fetch('/api/support/thread/read', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ thread_id: threadId, read_through: readThrough })
	});
	if (!response.ok) throw await failure(response, 'The conversation could not be marked as read.');
}

async function failure(response: Response, fallback: string) {
	const body = (await response.json().catch(() => null)) as {
		error?: string;
		field_errors?: Record<string, string>;
	} | null;
	const fieldMessage = body?.field_errors ? Object.values(body.field_errors)[0] : undefined;
	return httpError(response, fieldMessage ?? body?.error ?? fallback);
}

/** Starts a new chat with its first message. The same message id on a retry returns the same chat. */
export async function startSupportThread(input: {
	topic: SupportTopic;
	body: string;
	client_message_id: string;
}): Promise<SupportMessage & { thread_id: string }> {
	const response = await fetch('/api/support/threads', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	if (!response.ok) throw await failure(response, 'Your message could not be sent.');
	return response.json();
}

// The topic routes answer `changed: false` when the chat already had that topic.
async function changeTopic(url: string, topic: SupportTopic): Promise<void> {
	const response = await fetch(url, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ topic })
	});
	if (!response.ok) throw await failure(response, 'The topic could not be changed.');
}

export const changeSupportTopic = (threadId: string, topic: SupportTopic) =>
	changeTopic(`/api/support/threads/${threadId}`, topic);

export async function sendSupportMessage(input: {
	body: string;
	client_message_id: string;
	thread_id: string;
}): Promise<SupportMessage> {
	const response = await fetch('/api/support/messages', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	if (!response.ok) throw await failure(response, 'Your message could not be sent.');
	return response.json();
}

// Jafar's side ------------------------------------------------------------------------------------------

export type SupportInboxThread = {
	id: string;
	topic: SupportTopic;
	organization: { id: string; name: string };
	member_name: string;
	last_message_at: string;
	last_message_preview: string;
	/** `member` means the contractor wrote last, so the thread is waiting on Uplift. */
	last_message_sender_kind: SupportSenderKind;
	/** The contractor wrote after Uplift last opened the conversation. */
	unread: boolean;
};

export type SupportSettings = { responder_name: string; availability_note: string };

export type SupportInbox = {
	threads: SupportInboxThread[];
	has_more: boolean;
	settings: SupportSettings;
};

export type SupportInboxThreadDetail = {
	thread: SupportInboxThread;
	messages: SupportMessage[];
	has_earlier: boolean;
};

export const jafarSupportKey = ['jafar', 'support'] as const;
export const jafarSupportInboxKey = ['jafar', 'support', 'inbox'] as const;
export const jafarSupportInboxPageKey = (limit: number, topic: SupportTopic | null) =>
	[...jafarSupportInboxKey, limit, topic] as const;
export const jafarSupportUnreadKey = ['jafar', 'support', 'unread'] as const;
export const jafarSupportThreadKey = (threadId: string | null) =>
	['jafar', 'support', 'thread', threadId] as const;
export const jafarSupportThreadPageKey = (threadId: string | null, limit: number) =>
	[...jafarSupportThreadKey(threadId), limit] as const;

export async function fetchSupportInbox(
	limit: number,
	topic: SupportTopic | null
): Promise<SupportInbox> {
	const params = new URLSearchParams({ limit: String(limit) });
	if (topic) params.set('topic', topic);
	const response = await fetch(`/api/jafar/support/threads?${params}`);
	if (!response.ok) throw httpError(response, 'The Support Inbox could not be loaded.');
	return response.json();
}

export async function fetchSupportInboxThread(
	threadId: string,
	limit: number
): Promise<SupportInboxThreadDetail> {
	const response = await fetch(`/api/jafar/support/threads/${threadId}?limit=${limit}`);
	if (!response.ok) throw httpError(response, 'This conversation could not be loaded.');
	return response.json();
}

export async function fetchSupportInboxUnread(): Promise<SupportUnread> {
	const response = await fetch('/api/jafar/support/unread');
	if (!response.ok) throw httpError(response, 'Unread conversations could not be counted.');
	return response.json();
}

export async function markSupportInboxThreadRead(threadId: string, readThrough: string) {
	const response = await fetch(`/api/jafar/support/threads/${threadId}/read`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ read_through: readThrough })
	});
	if (!response.ok) throw await failure(response, 'The conversation could not be marked as read.');
}

/** The secret live channel name for this /jafar session. */
export async function fetchSupportOwnerTopic(): Promise<string> {
	const response = await fetch('/api/jafar/support/realtime', { method: 'POST' });
	if (!response.ok) throw await failure(response, 'Live updates could not be started.');
	return (await response.json()).topic;
}

export async function replyToSupportThread(
	threadId: string,
	input: { body: string; client_message_id: string }
): Promise<SupportMessage> {
	const response = await fetch(`/api/jafar/support/threads/${threadId}/messages`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	if (!response.ok) throw await failure(response, 'Your reply could not be sent.');
	return response.json();
}

export const jafarSupportPeopleKey = (threadId: string | null) =>
	[...jafarSupportThreadKey(threadId), 'people'] as const;

export async function fetchSupportInboxPeople(threadId: string): Promise<SupportPeople> {
	const response = await fetch(`/api/jafar/support/threads/${threadId}/people`);
	if (!response.ok)
		throw httpError(response, 'The people in this conversation could not be loaded.');
	return response.json();
}

export const changeSupportInboxTopic = (threadId: string, topic: SupportTopic) =>
	changeTopic(`/api/jafar/support/threads/${threadId}`, topic);

export const changeSupportInboxPeople = (threadId: string, userId: string, adding: boolean) =>
	changePeople(`/api/jafar/support/threads/${threadId}/people`, userId, adding);

export async function saveSupportSettings(input: SupportSettings): Promise<SupportSettings> {
	const response = await fetch('/api/jafar/support/settings', {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	if (!response.ok) throw await failure(response, 'Support settings could not be saved.');
	return (await response.json()).settings;
}
