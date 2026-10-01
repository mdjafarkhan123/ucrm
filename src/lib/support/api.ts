import { httpError } from '$lib/http-error';

// The Uplift Support Messenger: a team member writes to Uplift, Uplift answers from the /jafar Support Inbox.
// Separate from the contractor's own customer inbox in every way — its own tables, routes and cache keys
// (docs/client-onboarding-delivery-behavior-contract.md §7).

/** `system` and `ai` are reserved for later senders; nothing writes them yet. */
export type SupportSenderKind = 'member' | 'uplift' | 'system' | 'ai';

export type SupportMessage = {
	id: string;
	sender_kind: SupportSenderKind;
	sender_name: string;
	body: string;
	created_at: string;
};

export type SupportThread = {
	/** Null until the first message is sent. */
	thread_id: string | null;
	/** Oldest first. */
	messages: SupportMessage[];
	has_earlier: boolean;
	/** Uplift's own words for its hours and usual reply time. Empty when Uplift has not written one. */
	availability_note: string;
};

export const SUPPORT_MESSAGE_MAX_LENGTH = 4000;
export const SUPPORT_PAGE_SIZE = 50;
export const SUPPORT_MAX_LOADED = 500;
// Until live delivery arrives (D2), an open conversation asks again this often. A closed one asks nothing.
export const SUPPORT_OPEN_REFRESH_MS = 15_000;

// The user id is part of the key: the query client outlives sign-out, and a thread belongs to one person.
export const supportThreadKey = (userId: string | null) => ['support', 'thread', userId] as const;
export const supportThreadPageKey = (userId: string | null, limit: number) =>
	[...supportThreadKey(userId), limit] as const;

export async function fetchSupportThread(limit: number): Promise<SupportThread> {
	const response = await fetch(`/api/support/thread?limit=${limit}`);
	if (!response.ok) throw httpError(response, 'Your conversation could not be loaded.');
	return response.json();
}

async function failure(response: Response, fallback: string) {
	const body = (await response.json().catch(() => null)) as {
		error?: string;
		field_errors?: Record<string, string>;
	} | null;
	const fieldMessage = body?.field_errors ? Object.values(body.field_errors)[0] : undefined;
	return httpError(response, fieldMessage ?? body?.error ?? fallback);
}

export async function sendSupportMessage(input: {
	body: string;
	client_message_id: string;
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
	organization: { id: string; name: string };
	member_name: string;
	last_message_at: string;
	last_message_preview: string;
	/** `member` means the contractor wrote last, so the thread is waiting on Uplift. */
	last_message_sender_kind: SupportSenderKind;
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
export const jafarSupportInboxPageKey = (limit: number) =>
	[...jafarSupportInboxKey, limit] as const;
export const jafarSupportThreadKey = (threadId: string | null) =>
	['jafar', 'support', 'thread', threadId] as const;
export const jafarSupportThreadPageKey = (threadId: string | null, limit: number) =>
	[...jafarSupportThreadKey(threadId), limit] as const;

export async function fetchSupportInbox(limit: number): Promise<SupportInbox> {
	const response = await fetch(`/api/jafar/support/threads?limit=${limit}`);
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

export async function saveSupportSettings(input: SupportSettings): Promise<SupportSettings> {
	const response = await fetch('/api/jafar/support/settings', {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	if (!response.ok) throw await failure(response, 'Support settings could not be saved.');
	return (await response.json()).settings;
}
