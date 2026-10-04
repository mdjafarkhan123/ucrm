import { resolve } from '$app/paths';
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

// Only Uplift marks a chat Solved; anyone writing in it reopens it (D5a; Intercom's and Zendesk's model).
export type SupportStatus = 'open' | 'solved';

// Files in a chat (D4b): up to 5 files and 20 MB per message, from either side. Photos show in the chat;
// every other file downloads. Program files are refused, by the same list the customer inbox uses.
export const SUPPORT_MAX_ATTACHMENTS = 5;
export const SUPPORT_ATTACHMENT_TOTAL_BYTES = 20 * 1024 * 1024;

// The picture formats every browser can draw. Anything else — an iPhone HEIC, an SVG — is a file to
// download, never something shown from our own address.
const SUPPORT_PHOTO_MIME_TYPES = new Set([
	'image/jpeg',
	'image/png',
	'image/gif',
	'image/webp',
	'image/avif'
]);

export function isSupportPhoto(mimeType: string): boolean {
	return SUPPORT_PHOTO_MIME_TYPES.has(mimeType.toLowerCase());
}

/** A file stored with a message. */
export type SupportAttachment = {
	id: string;
	file_name: string;
	mime_type: string;
	byte_size: number;
	/** The browser made a small copy of the photo when it was attached. */
	has_thumbnail: boolean;
};

/** A file already uploaded to storage, named by the message that will carry it. */
export type SupportAttachmentUpload = {
	object_key: string;
	file_name: string;
	mime_type: string;
	has_thumbnail?: boolean;
};

export type SupportUploadTicket = {
	upload_url: string;
	object_key: string;
	/** Where a photo's small copy goes. Null for a file that is not a photo. */
	thumbnail_upload_url: string | null;
};

/** What a chat box hands over to be sent: words, files, or both. */
export type SupportOutgoingMessage = {
	body: string;
	client_message_id: string;
	attachments: SupportAttachmentUpload[];
};

export type SupportMessage = {
	id: string;
	sender_kind: SupportSenderKind;
	/** The team member who wrote it. Null for Uplift, system lines, and a member whose account is gone. */
	sender_user_id: string | null;
	sender_name: string;
	/** Empty when the message is files alone. */
	body: string;
	created_at: string;
	attachments: SupportAttachment[];
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
	status: SupportStatus;
	/** The setup section the chat was asked from (D6), in words. Null for an ordinary chat. */
	context_label: string | null;
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
	status: SupportStatus;
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

type UploadClaim = { fileName: string; mimeType: string; sizeBytes: number };

async function requestUploadTicket(url: string, file: UploadClaim): Promise<SupportUploadTicket> {
	const response = await fetch(url, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			file_name: file.fileName,
			mime_type: file.mimeType,
			size_bytes: file.sizeBytes
		})
	});
	if (!response.ok) throw await failure(response, 'That file could not be uploaded.');
	return response.json();
}

/** Asks for somewhere to upload a file the member is about to send. */
export const presignSupportAttachment = (file: UploadClaim) =>
	requestUploadTicket('/api/support/attachments/presign-upload', file);

/** Where a chat's files are read from: a member's own routes, or Jafar's. */
export type SupportFileUrls = {
	/** A photo, shown on the page. `thumb` is the small copy when one exists. */
	view: (attachment: SupportAttachment, size: 'thumb' | 'full') => string;
	download: (attachment: SupportAttachment) => string;
};

function fileUrls(fileUrl: (id: string) => string): SupportFileUrls {
	return {
		view: (attachment, size) =>
			size === 'thumb' && attachment.has_thumbnail
				? `${fileUrl(attachment.id)}?size=thumb`
				: fileUrl(attachment.id),
		download: (attachment) => `${fileUrl(attachment.id)}?download=1`
	};
}

export const supportFileUrls = fileUrls((id) => resolve('/api/support/attachments/[id]', { id }));
export const jafarSupportFileUrls = fileUrls((id) =>
	resolve('/api/jafar/support/attachments/[id]', { id })
);

/** Starts a new chat with its first message. The same message id on a retry returns the same chat. */
export async function startSupportThread(
	input: SupportOutgoingMessage & { topic: SupportTopic; context_section?: string }
): Promise<SupportMessage & { thread_id: string }> {
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

export async function sendSupportMessage(
	input: SupportOutgoingMessage & { thread_id: string }
): Promise<SupportMessage> {
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
	status: SupportStatus;
	/** Uplift sent the first message, to `member_name`. */
	opened_by_uplift: boolean;
	/** The setup section the member asked from (D6), in words. Null for an ordinary chat. */
	context_label: string | null;
};

/** Which chats the Support Inbox lists: open ones unless filtered. */
export type SupportInboxStatusFilter = SupportStatus | 'all';

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
export const jafarSupportInboxPageKey = (
	limit: number,
	topic: SupportTopic | null,
	status: SupportInboxStatusFilter
) => [...jafarSupportInboxKey, limit, topic, status] as const;
export const jafarSupportUnreadKey = ['jafar', 'support', 'unread'] as const;
export const jafarSupportThreadKey = (threadId: string | null) =>
	['jafar', 'support', 'thread', threadId] as const;
export const jafarSupportThreadPageKey = (threadId: string | null, limit: number) =>
	[...jafarSupportThreadKey(threadId), limit] as const;

export async function fetchSupportInbox(
	limit: number,
	topic: SupportTopic | null,
	status: SupportInboxStatusFilter
): Promise<SupportInbox> {
	const params = new URLSearchParams({ limit: String(limit), status });
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

/** Asks for somewhere to upload a file Uplift is about to send into this chat. */
export const presignSupportReplyAttachment = (threadId: string, file: UploadClaim) =>
	requestUploadTicket(`/api/jafar/support/threads/${threadId}/attachments/presign-upload`, file);

export async function replyToSupportThread(
	threadId: string,
	input: SupportOutgoingMessage
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

// The status route answers `changed: false` when the chat already had that status.
export async function changeSupportInboxStatus(threadId: string, status: SupportStatus) {
	const response = await fetch(`/api/jafar/support/threads/${threadId}/status`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ status })
	});
	if (!response.ok)
		throw await failure(
			response,
			status === 'solved'
				? 'The chat could not be marked solved.'
				: 'The chat could not be reopened.'
		);
}

/** A business's active team, owner first: who Uplift may start a chat with. */
export type SupportRecipient = { user_id: string; name: string; role: string };

export const jafarSupportRecipientsKey = (organizationId: string | null) =>
	[...jafarSupportKey, 'recipients', organizationId] as const;

export type SupportRecipients = {
	organization: { id: string; name: string };
	members: SupportRecipient[];
};

export async function fetchSupportRecipients(organizationId: string): Promise<SupportRecipients> {
	const response = await fetch(`/api/jafar/support/organizations/${organizationId}/members`);
	if (!response.ok) throw httpError(response, "This business's team could not be loaded.");
	return response.json();
}

/** Asks for somewhere to upload a file for a chat Uplift is about to start with this business. */
export const presignSupportStartAttachment = (organizationId: string, file: UploadClaim) =>
	requestUploadTicket(
		`/api/jafar/support/organizations/${organizationId}/attachments/presign-upload`,
		file
	);

/** Uplift starts a chat with one team member. Returns the first message, which names the new chat. */
export async function startSupportInboxThread(
	input: SupportOutgoingMessage & {
		organization_id: string;
		user_id: string;
		topic: SupportTopic;
		context_section?: string;
	}
): Promise<SupportMessage & { thread_id: string }> {
	const response = await fetch('/api/jafar/support/threads', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	if (!response.ok) throw await failure(response, 'Your message could not be sent.');
	return response.json();
}

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
