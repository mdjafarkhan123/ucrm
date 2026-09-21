import { httpError } from '$lib/http-error';
import type { ContextSection } from '$lib/communications/context-sections';
export type OutboundAttachment = {
	id: string;
	file_name: string;
	mime_type: string;
	byte_size: number;
};

export type InboxEmail = {
	id: string;
	client_id: string;
	channel: 'email' | 'sms';
	client_name: string;
	client_email: string | null;
	client_phone: string | null;
	quote_id: string | null;
	subject: string;
	text_content: string;
	status: string;
	failure_message: string | null;
	// Post-acceptance provider outcome. Null until a Brevo callback (email, Part 7.1) or a Twilio status
	// callback (sms, Stage 5A) lands for this message. The two vocabularies share this one column --
	// 'sms_'-namespaced so an email reputation window filtering on this field keeps counting only its own.
	delivery_outcome:
		| 'delivered'
		| 'soft_bounce'
		| 'hard_bounce'
		| 'complaint'
		| 'deferred'
		| 'blocked'
		| 'unsubscribed'
		| 'sms_delivered'
		| 'sms_undelivered'
		| 'sms_failed'
		| 'sms_needs_checking'
		| null;
	delivery_outcome_at: string | null;
	created_at: string;
	resent_from_intent_id: string | null;
	resent_into_intent_id: string | null;
	attachments: OutboundAttachment[];
	can_resend: boolean;
	// "Send Later": set only while status is 'queued' and this is still genuinely in the future -- see
	// emailStatusDisplay and can_cancel_scheduled below. Null for every ordinary (near-immediate) send.
	scheduled_at: string | null;
	can_cancel_scheduled: boolean;
	send_kind: string;
	created_by_name: string | null;
	assigned_to: string | null;
	assigned_to_name: string | null;
	is_following: boolean;
};

export type InboxEmailPage = {
	emails: InboxEmail[];
	next_cursor: string | null;
	view: 'team' | 'mine';
	can_view_team: boolean;
	can_manage_assignment: boolean;
	can_forward: boolean;
};

export type InboxAttachment = {
	id: string;
	file_name: string;
	mime_type: string;
	byte_size: number;
	status: string;
	failure_reason: string | null;
};

export type InboundInboxMessage = {
	direction: 'inbound';
	id: string;
	client_id: string | null;
	channel: 'email' | 'sms';
	client_name: string | null;
	sender_email: string | null;
	sender_phone: string | null;
	sender_name: string | null;
	subject: string;
	text_content: string;
	created_at: string;
	in_reply_to_intent_id: string | null;
	message_kind: string;
	review_status: string;
	review_reason: string | null;
	automation_suppressed: boolean;
	attachment_count: number;
	attachments: InboxAttachment[];
	unread: boolean;
	provider: string;
	provider_message_id: string | null;
	assigned_to: string | null;
	assigned_to_name: string | null;
	is_following: boolean;
};

export type OutboundInboxMessage = InboxEmail & { direction: 'outbound' };

export type EmailStatusDisplay = {
	label: string;
	tone: 'success' | 'warning' | 'critical' | 'inactive' | 'informative';
};

// Shared by the inbox timeline and the client Communication tab so a delivery status always reads the
// same way wherever an outbound message shows up.
export function outboundEmailStatus(email: OutboundInboxMessage): EmailStatusDisplay {
	return emailStatusDisplay(email);
}

// The same mapping, over just the fields it actually reads, so a send that has been accepted but has no
// stored row yet can label itself exactly as the row will once it arrives -- without that, the bubble
// would flip from one wording to another as the real message swaps in.
function formatScheduledAt(value: string) {
	return new Intl.DateTimeFormat(undefined, {
		month: 'short',
		day: 'numeric',
		hour: 'numeric',
		minute: '2-digit'
	}).format(new Date(value));
}

function emailStatusDisplay(email: {
	status: string;
	delivery_outcome?: OutboundInboxMessage['delivery_outcome'];
	failure_message?: string | null;
	scheduled_at?: string | null;
}): EmailStatusDisplay {
	// Once the provider has told us what happened after submission (Part 7.1), that outcome is the
	// truer status than "Submitted" and replaces it.
	if (email.status === 'submitted' && email.delivery_outcome) {
		switch (email.delivery_outcome) {
			case 'delivered':
				return { label: 'Delivered', tone: 'success' };
			case 'hard_bounce':
				return { label: 'Bounced', tone: 'critical' };
			case 'blocked':
				return { label: 'Blocked', tone: 'critical' };
			case 'complaint':
				return { label: 'Marked as spam', tone: 'critical' };
			case 'unsubscribed':
				return { label: 'Unsubscribed', tone: 'warning' };
			case 'soft_bounce':
			case 'deferred':
				return { label: 'Delivery delayed', tone: 'warning' };
			case 'sms_delivered':
				return { label: 'Delivered', tone: 'success' };
			case 'sms_undelivered':
				return { label: 'Not delivered', tone: 'critical' };
			case 'sms_failed':
				return { label: 'Failed', tone: 'critical' };
			case 'sms_needs_checking':
				return { label: 'Needs checking', tone: 'warning' };
		}
	}
	if (email.status === 'submitted') return { label: 'Submitted', tone: 'success' };
	if (email.status === 'queued') {
		// A genuinely future scheduled_at is a "Send Later" pick, not the worker holding the row back for
		// its own reasons -- those two only ever differ by a handful of seconds, so this reads real intent.
		if (email.scheduled_at && new Date(email.scheduled_at).getTime() > Date.now() + 60_000) {
			return {
				label: `Scheduled for ${formatScheduledAt(email.scheduled_at)}`,
				tone: 'informative'
			};
		}
		// A queued send the worker has already looked at and held back (quiet hours, an org not yet ready
		// to send, ...) carries a reason in failure_message; a freshly queued one has none yet.
		if (email.failure_message) return { label: 'Waiting to send', tone: 'informative' };
		return { label: 'Queued — not sent', tone: 'informative' };
	}
	if (email.status === 'claimed') return { label: 'Preparing to send', tone: 'warning' };
	if (email.status === 'cancelled') {
		// A send the worker refused because the address is suppressed reads differently from a plain cancel.
		if (email.failure_message?.includes('suppression list'))
			return { label: 'Blocked — suppressed address', tone: 'critical' };
		return { label: 'Cancelled', tone: 'inactive' };
	}
	if (email.status === 'failed') return { label: 'Retry scheduled', tone: 'critical' };
	return { label: 'Submission needs review', tone: 'warning' };
}

export type InboxMessage = OutboundInboxMessage | InboundInboxMessage;

// A reply the user has sent that has no server row yet. Messenger convention: the bubble appears the
// instant Send is pressed carrying its own delivery mark, so the timeline is never silent while the
// request is in flight, and `outboundEmailStatus` above takes over once the real row lands.
//
// `id` doubles as the idempotency key. Minting it per attempt rather than per request is what makes
// Retry safe: the reply endpoint dedupes on it (`target_logical_send_key`), so replaying a send that
// failed after the server had already accepted it cannot post a second copy.
export type PendingOutboundSend = {
	id: string;
	channel: 'email' | 'sms' | 'website_chat';
	subject: string | null;
	body: string;
	created_at: string;
	// 'sent' is the window between the server accepting the message and the timeline having re-read it.
	// The mark flips here, not when the re-read finishes -- acceptance is the fact the user is waiting on,
	// and the re-read only swaps in a row that says the same thing.
	state: 'sending' | 'sent' | 'failed';
	// What the server said it did with an accepted message, so the bubble can already carry the wording its
	// stored row will use. Null for channels with no delivery status of their own, like Website Chat.
	status: string | null;
	error: string;
	retry: () => void;
};

// What mark the bubble shows. An accepted email or SMS borrows the exact label its stored row will use
// (both share the same delivery-intent status vocabulary), so the swap is invisible; Website Chat has no
// delivery status, so an accepted chat message simply stops being marked and reads as an ordinary sent
// bubble.
export function pendingSendStatus(send: PendingOutboundSend): EmailStatusDisplay | null {
	if (send.state === 'sending') return { label: 'Sending…', tone: 'informative' };
	if (send.state === 'failed') return { label: 'Not sent', tone: 'critical' };
	if ((send.channel === 'email' || send.channel === 'sms') && send.status)
		return emailStatusDisplay({ status: send.status });
	return null;
}

// Website Chat (Part WC4.5). One message in a chat thread. `direction` is derived server-side from
// sender_type, so a 'system' part -- the line that says a conversation ended -- reads as outbound and
// renders as a note, never as somebody speaking.
export type WebsiteChatInboxMessage = {
	channel: 'website_chat';
	direction: 'inbound' | 'outbound';
	id: string;
	client_id: string | null;
	client_name: string | null;
	session_id: string;
	sender_type: 'visitor' | 'staff' | 'system' | 'automation';
	sender_user_id: string | null;
	sender_name: string | null;
	body: string;
	delivery_state: string;
	created_at: string;
	unread: boolean;
	assigned_to: string | null;
	assigned_to_name: string | null;
	is_following: boolean;
};

// The two Clients a conflicting-identity session is caught between. UCRM never picks -- a person does.
export type WebsiteChatIdentityCandidate = {
	matched_on: 'phone' | 'email';
	client_id: string;
	client_name: string;
};

// Per conversation, not per message: everything a chat thread knows about itself that a single bubble
// cannot carry -- who the visitor is before they have a contact, and whether it has ended.
export type WebsiteChatInboxSession = {
	id: string;
	client_id: string | null;
	client_name: string | null;
	match_status: 'resolved' | 'needs_review';
	visitor_name: string;
	visitor_email: string | null;
	visitor_phone: string | null;
	started_at: string;
	last_activity_at: string;
	closed_at: string | null;
	closed_reason: string | null;
	closed_by: string | null;
	closed_by_name: string | null;
	candidates: WebsiteChatIdentityCandidate[];
};

export type InboxMessagePage = {
	emails: InboxEmail[];
	messages: InboxMessage[];
	// Beside `messages`, not inside it: the paging merge already happened server-side, and keeping the
	// email-shaped union untouched is what lets Website Chat land without disturbing a shipped screen.
	website_chat: WebsiteChatInboxMessage[];
	website_chat_sessions: WebsiteChatInboxSession[];
	next_cursor: string | null;
	view: 'team' | 'mine';
	can_view_team: boolean;
	can_manage_assignment: boolean;
	can_forward: boolean;
	can_send: boolean;
};

// One item in a conversation's merged timeline -- an email-shaped message or a Website Chat one. Kept as
// a union rather than folding chat into `InboxMessage` so every shipped `direction === 'inbound'`
// narrowing on the email union stays untouched (see `InboxMessagePage` above).
export type TimelineMessage = InboxMessage | WebsiteChatInboxMessage;

export function isWebsiteChatMessage(item: TimelineMessage): item is WebsiteChatInboxMessage {
	return 'channel' in item && item.channel === 'website_chat';
}

export type ConversationGroup = {
	/** `client_id` for a known contact, `guarded:<sender_email>` for an unresolved email sender, or
	 *  `webchat:<sessionId>` for a conflicting-identity chat session. */
	key: string;
	clientId: string | null;
	name: string;
	avatarId: string;
	/** Most recent item, either channel or direction — drives the list-row preview. */
	latest: TimelineMessage;
	/** Unread inbound items in this group; a guarded group has no read-mark seam, so it never clears. */
	unreadCount: number;
	/** Full history, oldest first, for the conversation timeline. */
	messages: TimelineMessage[];
	guarded: boolean;
	/** The address a guarded email group is grouped by, and the only way to address it before it has a client. */
	senderEmail: string | null;
	/** Constant across every message in the group -- assignment/following are per-conversation, not per-message. */
	assignedTo: string | null;
	assignedToName: string | null;
	isFollowing: boolean;
	/** The most recently active Website Chat session touching this conversation, if any -- drives the
	 *  composer's channel tab, the ended state, the end-session control and the needs-review banner. */
	chatSession: WebsiteChatInboxSession | null;
};

function timelineItemKey(item: TimelineMessage): string {
	if (item.client_id) return item.client_id;
	if (isWebsiteChatMessage(item)) return `webchat:${item.session_id}`;
	// Only an inbound message can otherwise lack a client_id (an outbound send always targets a known
	// client). An unresolved sender is grouped by whichever address the channel actually carries.
	const inbound = item as InboundInboxMessage;
	return inbound.channel === 'sms'
		? `guarded-sms:${inbound.sender_phone}`
		: `guarded:${inbound.sender_email}`;
}

function timelineItemName(
	item: TimelineMessage,
	session: WebsiteChatInboxSession | undefined
): string {
	if (isWebsiteChatMessage(item)) return item.client_name ?? session?.visitor_name ?? 'Visitor';
	if (item.direction === 'outbound') return item.client_name;
	return item.client_name ?? item.sender_name ?? item.sender_email ?? item.sender_phone ?? '';
}

function timelineItemAvatarId(item: TimelineMessage): string {
	if (item.client_id) return item.client_id;
	if (isWebsiteChatMessage(item)) return item.session_id;
	const inbound = item as InboundInboxMessage;
	return inbound.channel === 'sms' ? (inbound.sender_phone ?? '') : (inbound.sender_email ?? '');
}

/**
 * Groups a chronologically-descending page (email plus Website Chat, merged and re-sorted) into one row
 * per contact, matching HighLevel's contact-centered Conversations list. An item with no client_id groups
 * by sender email (unresolved email sender) or by session id (conflicting-identity chat session) instead,
 * so distinct unresolved conversations stay distinguishable for later review rather than collapsing into
 * one opaque bucket.
 */
export function groupMessagesByContact(
	messages: InboxMessage[],
	websiteChat: WebsiteChatInboxMessage[] = [],
	websiteChatSessions: WebsiteChatInboxSession[] = []
): ConversationGroup[] {
	const sessionsById = new Map(websiteChatSessions.map((session) => [session.id, session]));
	// Both inputs already arrive sorted newest-first; merging and re-sorting keeps that order across the
	// combined timeline so a single descending pass (below) can build each group in one go.
	const timeline: TimelineMessage[] = [...messages, ...websiteChat].sort(
		(a, b) => b.created_at.localeCompare(a.created_at) || b.id.localeCompare(a.id)
	);

	const groups = new Map<string, ConversationGroup>();
	for (const item of timeline) {
		const key = timelineItemKey(item);
		const session = isWebsiteChatMessage(item) ? sessionsById.get(item.session_id) : undefined;
		let group = groups.get(key);
		if (!group) {
			group = {
				key,
				clientId: item.client_id,
				name: timelineItemName(item, session),
				avatarId: timelineItemAvatarId(item),
				latest: item,
				unreadCount: 0,
				messages: [],
				guarded: item.client_id === null,
				senderEmail:
					!isWebsiteChatMessage(item) && item.client_id === null
						? (item as InboundInboxMessage).sender_email
						: null,
				assignedTo: item.assigned_to,
				assignedToName: item.assigned_to_name,
				isFollowing: item.is_following,
				chatSession: null
			};
			groups.set(key, group);
		}
		group.messages.push(item);
		if (item.direction === 'inbound' && item.unread) group.unreadCount += 1;
		if (
			session &&
			(!group.chatSession || session.last_activity_at > group.chatSession.last_activity_at)
		) {
			group.chatSession = session;
		}
	}
	for (const group of groups.values()) group.messages.reverse();
	return [...groups.values()];
}

// A forward event (send_kind 'forward') is direction 'outbound' for timeline placement, but it targets an
// external address, never the customer's own -- it has no bearing on "who a reply goes to." Both call sites
// that derive the customer's address from the most recent outbound-shaped message skip a forward row and
// fall back to the next one, matching the reply route's own server-side resolution (which has no knowledge
// of forward events at all). A Website Chat row has no email address at all and is skipped the same way.
export function conversationCustomerEmail(group: ConversationGroup): string {
	for (let index = group.messages.length - 1; index >= 0; index -= 1) {
		const message = group.messages[index];
		if (isWebsiteChatMessage(message)) continue;
		// An SMS-channel message has no email address of its own -- skip it and keep looking, the same way
		// a forward row or a Website Chat message is skipped.
		if (message.direction === 'inbound' && message.sender_email) return message.sender_email;
		if (message.direction === 'outbound' && message.send_kind !== 'forward' && message.client_email)
			return message.client_email;
	}
	return '';
}

// The SMS mirror of conversationCustomerEmail: the phone number an SMS reply would target, matching the
// reply command's own "most recent activity, phone contact methods only" resolution.
export function conversationCustomerPhone(group: ConversationGroup): string {
	for (let index = group.messages.length - 1; index >= 0; index -= 1) {
		const message = group.messages[index];
		if (isWebsiteChatMessage(message)) continue;
		if (message.direction === 'inbound' && message.sender_phone) return message.sender_phone;
		if (message.direction === 'outbound' && message.send_kind !== 'forward' && message.client_phone)
			return message.client_phone;
	}
	return '';
}

export type InboxView = 'team' | 'mine';

export const inboxEmailKey = (search: string) =>
	['communications', 'inbox', 'email', search] as const;

export const inboxMessagesKey = (search: string, view: InboxView = 'team') =>
	['communications', 'inbox', 'messages', view, search] as const;

export async function fetchInboxEmail(search = ''): Promise<InboxEmailPage> {
	const params = new URLSearchParams();
	if (search.trim()) params.set('search', search.trim());
	const response = await fetch(`/api/communications/email-history?${params.toString()}`);
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw httpError(response, result.error ?? 'Email history could not be loaded.');
	return result as InboxEmailPage;
}

export async function fetchInboxMessages(
	search = '',
	view: InboxView = 'team'
): Promise<InboxMessagePage> {
	const params = new URLSearchParams({ channel: 'all' });
	if (search.trim()) params.set('search', search.trim());
	if (view === 'mine') params.set('view', 'mine');
	const response = await fetch(`/api/communications/email-history?${params.toString()}`);
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'Conversation history could not be loaded.');
	return result as InboxMessagePage;
}

export async function assignConversation(clientId: string, assignedTo: string | null) {
	const response = await fetch(`/api/communications/conversations/${clientId}/assignment`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ assigned_to: assignedTo })
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'This conversation could not be assigned.');
	return result as { assigned_to: string | null };
}

export async function followConversation(clientId: string) {
	const response = await fetch(`/api/communications/conversations/${clientId}/followers`, {
		method: 'POST'
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'This conversation could not be followed.');
	return result as { following: boolean };
}

export async function unfollowConversation(clientId: string) {
	const response = await fetch(`/api/communications/conversations/${clientId}/followers`, {
		method: 'DELETE'
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'This conversation could not be unfollowed.');
	return result as { following: boolean };
}

export type OutboundAttachmentPayload = {
	object_key: string;
	file_name: string;
	mime_type: string;
};

export async function presignOutboundAttachment(input: {
	fileName: string;
	mimeType: string;
	sizeBytes: number;
	channel?: 'email' | 'sms';
}) {
	const response = await fetch('/api/communications/attachments/presign-upload', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			file_name: input.fileName,
			mime_type: input.mimeType,
			size_bytes: input.sizeBytes,
			channel: input.channel ?? 'email'
		})
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'That file could not be prepared for upload.');
	return result as { upload_url: string; object_key: string };
}

// `idempotencyKey` belongs to the send attempt, not to this call, so a retry of the same attempt passes
// the same key back and the endpoint dedupes it. Callers with nothing to retry can let it default.
export async function sendConversationReply(
	clientId: string,
	subject: string,
	body: string,
	attachments: OutboundAttachmentPayload[] = [],
	idempotencyKey: string = crypto.randomUUID(),
	// "Send Later": an ISO instant to hold the email until, instead of sending it now. Email only.
	scheduledAt: string | null = null
) {
	const response = await fetch(`/api/communications/conversations/${clientId}/reply`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			channel: 'email',
			subject,
			body,
			idempotency_key: idempotencyKey,
			attachments,
			...(scheduledAt ? { scheduled_at: scheduledAt } : {})
		})
	});
	const result = (await response.json().catch(() => ({}))) as {
		error?: string;
		field_errors?: Record<string, string>;
		intent?: { id: string; status: string; created_at: string };
	};
	if (!response.ok) {
		const error = new Error(result.error ?? 'This reply could not be queued.') as Error & {
			fieldErrors?: Record<string, string>;
		};
		error.fieldErrors = result.field_errors;
		throw error;
	}
	return result as { intent: { id: string; status: string; created_at: string } };
}

// SMS mirror of sendConversationReply: no subject, at most one photo (Stage 6D-2). Same idempotency
// contract -- `idempotencyKey` belongs to the send attempt, and the endpoint dedupes a retry on it.
export async function sendConversationReplySms(
	clientId: string,
	body: string,
	attachments: OutboundAttachmentPayload[] = [],
	idempotencyKey: string = crypto.randomUUID()
) {
	const response = await fetch(`/api/communications/conversations/${clientId}/reply`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ channel: 'sms', body, idempotency_key: idempotencyKey, attachments })
	});
	const result = (await response.json().catch(() => ({}))) as {
		error?: string;
		field_errors?: Record<string, string>;
		intent?: { id: string; status: string; created_at: string };
	};
	if (!response.ok) {
		const error = new Error(result.error ?? 'This text could not be queued.') as Error & {
			fieldErrors?: Record<string, string>;
		};
		error.fieldErrors = result.field_errors;
		throw error;
	}
	return result as { intent: { id: string; status: string; created_at: string } };
}

export type SmsReplyEstimate =
	| {
			ready: true;
			encoding: string;
			segment_count: number;
			cost_minor: number;
			currency: string;
			sender_phone: string;
			mms_eligible: boolean;
	  }
	| { ready: false; reason: string; mms_eligible: boolean };

// The composer's live impact line, plus (Stage 6D-2) whether the current sender can attach a photo --
// resolved from the sender alone, so it comes back even for an empty draft. Never throws on a normal
// "not ready yet" outcome (no sender, no published rate) -- those come back as {ready: false, reason} for
// the composer to show inline; only a genuine request failure throws.
export async function estimateSmsReply(clientId: string, body: string): Promise<SmsReplyEstimate> {
	const response = await fetch(`/api/communications/conversations/${clientId}/sms-estimate`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ body })
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw httpError(response, result.error ?? 'This estimate could not be loaded.');
	return result as SmsReplyEstimate;
}

export async function forwardInboundMessage(
	clientId: string,
	messageId: string,
	recipients: string[],
	subject: string,
	body: string,
	attachmentIds: string[] = []
) {
	const response = await fetch(
		`/api/communications/conversations/${clientId}/messages/${messageId}/forward`,
		{
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({
				recipients,
				subject,
				body,
				attachment_ids: attachmentIds,
				idempotency_key: crypto.randomUUID()
			})
		}
	);
	const result = (await response.json().catch(() => ({}))) as {
		error?: string;
		field_errors?: Record<string, string>;
		event?: { id: string; status: string; created_at: string };
	};
	if (!response.ok) {
		const error = new Error(result.error ?? 'This message could not be forwarded.') as Error & {
			fieldErrors?: Record<string, string>;
		};
		error.fieldErrors = result.field_errors;
		throw error;
	}
	return result as { event: { id: string; status: string; created_at: string } };
}

// A guarded conversation has no client_id, so it is addressed by the sender's own address -- the same
// key groupMessagesByContact groups it under.
export async function resolveInboundReview(
	senderEmail: string,
	resolution: 'link' | 'dismiss',
	clientId: string | null
) {
	const response = await fetch('/api/communications/review', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			sender_email: senderEmail,
			resolution,
			client_id: resolution === 'link' ? clientId : null
		})
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'This conversation could not be resolved.');
	return result as {
		resolution: 'link' | 'dismiss';
		resolved_count: number;
		client_id: string | null;
	};
}

export async function resendInboxEmail(id: string, idempotencyKey: string) {
	const response = await fetch(`/api/communications/${id}/resend`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ idempotency_key: idempotencyKey })
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw httpError(response, result.error ?? 'This message could not be resent.');
	return result as { intent: { id: string; status: string; created_at: string } };
}

// Cancels a "Send Later" email before the worker claims it -- see cancel_communication_conversation_reply.
export async function cancelScheduledConversationReply(id: string) {
	const response = await fetch(`/api/communications/${id}/cancel-scheduled`, { method: 'POST' });
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'This scheduled message could not be cancelled.');
	return result as { intent: { id: string; status: string } };
}

export async function markConversationRead(clientId: string) {
	const response = await fetch('/api/communications/read-marks', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ client_id: clientId })
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'This conversation could not be marked read.');
	return result as { last_read_at: string };
}

export async function fetchInboundAttachmentDownloadUrl(attachmentId: string) {
	const response = await fetch(`/api/communications/inbound-attachments/${attachmentId}/download`);
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw httpError(response, result.error ?? 'That file could not be downloaded.');
	return result as { download_url: string };
}

export async function fetchOutboundAttachmentDownloadUrl(attachmentId: string) {
	const response = await fetch(`/api/communications/attachments/${attachmentId}/download`);
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw httpError(response, result.error ?? 'That file could not be downloaded.');
	return result as { download_url: string };
}

// --- Part 5D: work-context panel + client Communication tab -----------------------------------------

export type ConversationContextProperty = {
	id: string;
	label: string;
	address_line1: string;
	city: string;
	state_region: string | null;
	postal_code: string | null;
};

export type ConversationContextRequest = {
	id: string;
	title: string;
	status: string;
	created_at: string;
};

export type ConversationContextQuote = {
	id: string;
	quote_number: number;
	title: string;
	status: string;
	currency_code: string;
	created_at: string;
	/** `null` when this member may not see prices -- withheld, never zeroed. */
	total_minor: number | null;
};

export type ConversationContextOpportunity = {
	id: string;
	title: string;
	stage: string;
	outcome: string;
	created_at: string;
};

export type ConversationContextJob = {
	id: string;
	job_number: number;
	title: string;
	derived_status: string;
	currency_code: string;
	created_at: string;
	total_minor: number | null;
};

export type ConversationContextInvoice = {
	id: string;
	invoice_number: number;
	subject: string;
	derived_status: string;
	currency_code: string;
	due_date: string;
	created_at: string;
	total_minor: number | null;
	remaining_minor: number | null;
};

// What opening a conversation loads: the client, and which record tabs this member may see. Each tab's
// records are a separate read (`fetchConversationContextSection`) made only when the tab is reached for.
export type ConversationContext = {
	client: {
		id: string;
		display_name: string;
		company_name: string | null;
		client_type: string;
		email: string | null;
		phone: string | null;
	};
	sections: ContextSection[];
};

export type ContextSectionRows = {
	properties: ConversationContextProperty[];
	requests: ConversationContextRequest[];
	quotes: ConversationContextQuote[];
	jobs: ConversationContextJob[];
	invoices: ConversationContextInvoice[];
	pipeline: ConversationContextOpportunity[];
};

export type ContextSectionPage<S extends ContextSection = ContextSection> = {
	items: ContextSectionRows[S];
	has_more: boolean;
	locale: string;
};

export const conversationContextKey = (clientId: string) =>
	['communications', 'conversation-context', clientId] as const;

// Nested under the client's context key on purpose: everything that already invalidates that key after a
// follow or an assignment change refreshes the open tab too.
export const conversationContextSectionKey = (clientId: string, section: ContextSection) =>
	[...conversationContextKey(clientId), section] as const;

export async function fetchConversationContext(clientId: string): Promise<ConversationContext> {
	const response = await fetch(`/api/communications/conversations/${clientId}/context`);
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'Customer context could not be loaded.');
	return result as ConversationContext;
}

// Whether each of a customer's phone numbers may be texted, and the customer's marketing-email standing.
// `stopped_by` says who stopped it: the customer's own STOP is locked, a staff stop can be taken back.
export type ConversationMessagingPhone = {
	contact_method_id: string;
	value: string;
	is_primary: boolean;
	state: 'opted_in' | 'opted_out' | 'unknown';
	stopped_by: 'customer' | 'staff' | null;
	stopped_at: string | null;
	stopped_by_name: string | null;
	note: string | null;
	can_undo: boolean;
};

export type ConversationMessaging = {
	can_manage: boolean;
	phones: ConversationMessagingPhone[];
	marketing_email: {
		email: string;
		state: 'opted_in' | 'opted_out' | 'unknown';
		effective_at: string | null;
	} | null;
};

// Nested under the client's context key so the invalidation a follow or assignment change already does
// refreshes this too, and so a stop or restart can invalidate just this.
export const conversationMessagingKey = (clientId: string) =>
	[...conversationContextKey(clientId), 'messaging'] as const;

export async function fetchConversationMessaging(clientId: string): Promise<ConversationMessaging> {
	const response = await fetch(`/api/communications/conversations/${clientId}/sms-stop`);
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'Messaging status could not be loaded.');
	return result as ConversationMessaging;
}

export async function changeSmsStop(
	clientId: string,
	input: { contact_method_id: string; action: 'stop' | 'undo'; note?: string }
): Promise<void> {
	const response = await fetch(`/api/communications/conversations/${clientId}/sms-stop`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw httpError(response, result.error ?? 'That change could not be saved.');
}

export async function fetchConversationContextSection<S extends ContextSection>(
	clientId: string,
	section: S
): Promise<ContextSectionPage<S>> {
	const response = await fetch(
		`/api/communications/conversations/${clientId}/context?section=${section}`
	);
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw httpError(response, result.error ?? 'That could not be loaded.');
	return result as ContextSectionPage<S>;
}

export const clientCommunicationHistoryKey = (clientId: string) =>
	['communications', 'client-history', clientId] as const;

// Same merged inbound/outbound shape and cursor format `fetchInboxMessages` already uses -- the client
// Communication tab is that same history read scoped to one client, not a second timeline architecture.
export async function fetchClientCommunicationHistory(
	clientId: string,
	cursor?: string
): Promise<InboxMessagePage> {
	const params = new URLSearchParams({ client_id: clientId });
	if (cursor) params.set('cursor', cursor);
	const response = await fetch(`/api/communications/email-history?${params.toString()}`);
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'Communication history could not be loaded.');
	return result as InboxMessagePage;
}

// --- Website Chat, staff side (WC4.5 Layer 3) --------------------------------------------------------

// A staff reply into a live Website Chat session, addressed by session id since a conflicting-identity
// session has no client_id yet and is still a real, replyable conversation.
export async function sendWebsiteChatStaffMessage(
	sessionId: string,
	body: string,
	idempotencyKey: string
) {
	const response = await fetch(`/api/communications/website-chat/sessions/${sessionId}/messages`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ body, idempotency_key: idempotencyKey })
	});
	const result = (await response.json().catch(() => ({}))) as {
		error?: string;
		field_errors?: Record<string, string>;
	};
	if (!response.ok) {
		const error = new Error(result.error ?? 'This reply could not be sent.') as Error & {
			fieldErrors?: Record<string, string>;
		};
		error.fieldErrors = result.field_errors;
		throw error;
	}
	return result;
}

export async function endWebsiteChatSession(sessionId: string) {
	const response = await fetch(`/api/communications/website-chat/sessions/${sessionId}/end`, {
		method: 'POST'
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'This conversation could not be ended.');
	return result;
}

// There is deliberately no dismiss path for a conflicting-identity session -- see
// `WebsiteChatResolveIdentitySchema` on the server.
export async function resolveWebsiteChatIdentity(sessionId: string, clientId: string) {
	const response = await fetch(`/api/communications/website-chat/sessions/${sessionId}/identity`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ client_id: clientId })
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'This identity could not be resolved.');
	return result;
}
