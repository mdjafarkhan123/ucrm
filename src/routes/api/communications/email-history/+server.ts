import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { hasPermission } from '$lib/server/access/permission';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';

const PAGE_SIZE = 50;
// The client Communication tab (Part 5D) reads a single client's full history rather than the whole
// inbox, so it pages in the smaller unit the tab's own "Load older" button was approved for.
const CLIENT_HISTORY_PAGE_SIZE = 25;
// A conflicting-identity Website Chat session is a staff to-do, not a backlog: an organization that has
// let a hundred pile up has a triage problem, not a paging problem. Bounding the scan keeps this read a
// fixed cost no matter how many accumulate.
const NEEDS_REVIEW_SESSION_SCAN = 100;

const WEBSITE_CHAT_MESSAGE_COLUMNS =
	'id, client_id, session_id, sender_type, sender_user_id, body, delivery_state, created_at';

// website_chat_messages_visitor_direction_check already guarantees this pairing in the data, so the
// direction column itself never has to be read -- one fewer column on every page of the merged feed.
const chatDirection = (senderType: string) => (senderType === 'visitor' ? 'inbound' : 'outbound');

function readCursor(value: string | null) {
	if (!value) return null;
	const separator = value.lastIndexOf('|');
	if (separator < 1) return null;
	const createdAt = value.slice(0, separator);
	const id = value.slice(separator + 1);
	if (Number.isNaN(Date.parse(createdAt)) || !id) return null;
	return { createdAt, id };
}

function escapeSearch(search: string) {
	return search.replace(/[\\%_]/g, (match) => `\\${match}`).replace(/"/g, '\\"');
}

export const GET: RequestHandler = async (event) => {
	const auth = await getOrganizationContext(event);
	if (!auth) {
		return json(
			{ error: 'Authentication or organization membership required.' },
			{ status: 401, headers: PRIVATE_READ_HEADERS }
		);
	}

	let access;
	try {
		access = await resolveOrganizationAccess(
			event.locals.supabase,
			auth.organization.id,
			auth.user.id
		);
	} catch (error) {
		console.error('Could not resolve inbox access.', error);
		return databaseError();
	}

	const canViewTeam = hasPermission(access, 'conversations.view_team');
	const canViewAssigned = hasPermission(access, 'conversations.view_assigned');
	const canManageAssignment = hasPermission(access, 'conversations.manage_assignment');
	const canForward = hasPermission(access, 'conversations.forward');
	const canSend = hasPermission(access, 'conversations.send');
	if (!canViewTeam && !canViewAssigned) {
		return json(
			{ error: 'You do not have access to conversations.', reason: 'permission_denied' },
			{ status: 403, headers: PRIVATE_READ_HEADERS }
		);
	}

	// Team Inbox is only ever offered to someone who can see it; an assigned-only viewer always gets My
	// Inbox regardless of what the query string asks for.
	const view: 'team' | 'mine' =
		canViewTeam && event.url.searchParams.get('view') !== 'mine' ? 'team' : 'mine';

	const organizationId = auth.organization.id;
	// The client Communication tab asks for one client's history by id -- always both directions, never
	// searched, and paged in its own smaller unit. `view`'s existing "mine" restriction below still applies
	// unchanged: an assigned-only viewer only ever sees this client's messages when the client is already
	// theirs, exactly as it already restricts the general inbox.
	const requestedClientId = event.url.searchParams.get('client_id');
	const includeInbound =
		requestedClientId !== null || event.url.searchParams.get('channel') === 'all';
	const search = requestedClientId ? '' : (event.url.searchParams.get('search')?.trim() ?? '');
	const cursor = readCursor(event.url.searchParams.get('cursor'));
	const pageSize = requestedClientId ? CLIENT_HISTORY_PAGE_SIZE : PAGE_SIZE;
	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communications_inbox_read:${organizationId}:${auth.user.id}`,
			windowSeconds: 60,
			maxAttempts: 120
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'private, no-cache');
			return response;
		}
	} catch (error) {
		console.error('Could not rate-limit inbox access.', error);
		return databaseError();
	}

	// My Inbox is every conversation assigned to or followed by the caller. A guarded/unresolved-sender
	// message has no client_id and so can never be "mine" -- Part 5C's forward/attach flow is the only
	// path that gives one a contact identity.
	let myClientIds: string[] | null = null;
	if (view === 'mine') {
		const [assignedResult, followedResult] = await Promise.all([
			ownerClient
				.from('communication_conversation_assignments')
				.select('client_id')
				.eq('organization_id', organizationId)
				.eq('assigned_to', auth.user.id),
			ownerClient
				.from('communication_conversation_followers')
				.select('client_id')
				.eq('organization_id', organizationId)
				.eq('user_id', auth.user.id)
		]);
		if (assignedResult.error || followedResult.error) return databaseError();
		myClientIds = [
			...new Set([
				...(assignedResult.data ?? []).map((row) => row.client_id),
				...(followedResult.data ?? []).map((row) => row.client_id)
			])
		];
		if (myClientIds.length === 0) {
			return json(
				{
					emails: [],
					messages: [],
					website_chat: [],
					website_chat_sessions: [],
					next_cursor: null,
					view,
					can_view_team: canViewTeam,
					can_manage_assignment: canManageAssignment,
					can_forward: canForward,
					can_send: canSend
				},
				{ headers: PRIVATE_READ_HEADERS }
			);
		}
	}

	// Part WC4.5: a conflicting-identity ("needs review") Website Chat session carries client_id = null on
	// the session AND on every one of its messages, by design -- that is what keeps the thread out of both
	// candidate contacts' history while the conflict stands. So those messages are invisible to the partial
	// index the merged feed rides, and they can never be "mine", exactly the rule guarded inbound email
	// already follows. They come from their own bounded read off website_chat_sessions_needs_review_idx.
	let reviewSessionIds: string[] = [];
	if (includeInbound && !requestedClientId && !myClientIds) {
		const reviewSessions = await ownerClient
			.from('website_chat_sessions')
			.select('id')
			.eq('organization_id', organizationId)
			.eq('match_status', 'needs_review')
			.order('started_at', { ascending: false })
			.limit(NEEDS_REVIEW_SESSION_SCAN);
		if (reviewSessions.error) {
			console.error('Could not load Website Chat sessions awaiting review.', reviewSessions.error);
			return databaseError();
		}
		reviewSessionIds = (reviewSessions.data ?? []).map((row) => row.id);
	}

	let outboundQuery = ownerClient
		.from('communication_delivery_intents')
		.select(
			'id, client_id, recipient_email, quote_id, subject, text_content, status, failure_message, created_at, resent_from_intent_id, send_kind, created_by, delivery_outcome, delivery_outcome_at'
		)
		.eq('organization_id', organizationId)
		.order('created_at', { ascending: false })
		.order('id', { ascending: false });
	if (requestedClientId) outboundQuery = outboundQuery.eq('client_id', requestedClientId);
	if (search) {
		const escaped = escapeSearch(search);
		outboundQuery = outboundQuery.or(
			`subject.ilike."%${escaped}%",recipient_email.ilike."%${escaped}%"`
		);
	}
	if (cursor) {
		outboundQuery = outboundQuery
			.lte('created_at', cursor.createdAt)
			.or(
				`created_at.lt.${cursor.createdAt},and(created_at.eq.${cursor.createdAt},id.lt.${cursor.id})`
			);
	}
	if (myClientIds) outboundQuery = outboundQuery.in('client_id', myClientIds);
	// A merged page still needs at most pageSize outbound rows to compute the true top pageSize + 1 of the
	// combined feed (see the merge below) -- fetching pageSize + 1 from each side is always enough.
	const fetchLimit = pageSize + 1;

	let inboundQuery = includeInbound
		? ownerClient
				.from('communication_inbound_messages')
				.select(
					'id, client_id, sender_email, sender_name, subject, text_content, created_at, in_reply_to_intent_id, message_kind, review_status, review_reason, automation_suppressed, attachment_count, provider, provider_message_id'
				)
				.eq('organization_id', organizationId)
				// A dismissed guarded message is triaged away, not deleted -- it keeps its audit row but
				// leaves the inbox for good (Part 5C-i).
				.neq('review_status', 'dismissed')
				.order('created_at', { ascending: false })
				.order('id', { ascending: false })
		: null;
	if (inboundQuery && requestedClientId)
		inboundQuery = inboundQuery.eq('client_id', requestedClientId);
	if (inboundQuery && search) {
		const escaped = escapeSearch(search);
		inboundQuery = inboundQuery.or(
			`subject.ilike."%${escaped}%",sender_email.ilike."%${escaped}%",sender_name.ilike."%${escaped}%"`
		);
	}
	if (inboundQuery && cursor) {
		inboundQuery = inboundQuery
			.lte('created_at', cursor.createdAt)
			.or(
				`created_at.lt.${cursor.createdAt},and(created_at.eq.${cursor.createdAt},id.lt.${cursor.id})`
			);
	}
	// A guarded/unresolved-sender message has no client_id, so it is never "mine" -- excluding it here
	// matches groupMessagesByContact's existing rule that a guarded conversation is never marked read.
	if (inboundQuery && myClientIds) inboundQuery = inboundQuery.in('client_id', myClientIds);

	// Part 5C-ii: a resolved conversation's forward events join the same merged timeline as a third source.
	// A forward always has a client_id -- enqueue_inbound_message_forward requires the source message to
	// already be resolved onto a client -- so it needs no guarded-sender handling the way inbound does.
	let forwardQuery = includeInbound
		? ownerClient
				.from('communication_forward_events')
				.select(
					'id, client_id, recipient_emails, subject, text_content, status, failure_message, created_at, created_by'
				)
				.eq('organization_id', organizationId)
				.order('created_at', { ascending: false })
				.order('id', { ascending: false })
		: null;
	if (forwardQuery && requestedClientId)
		forwardQuery = forwardQuery.eq('client_id', requestedClientId);
	if (forwardQuery && search) {
		forwardQuery = forwardQuery.ilike('subject', `%${escapeSearch(search)}%`);
	}
	if (forwardQuery && cursor) {
		forwardQuery = forwardQuery
			.lte('created_at', cursor.createdAt)
			.or(
				`created_at.lt.${cursor.createdAt},and(created_at.eq.${cursor.createdAt},id.lt.${cursor.id})`
			);
	}
	if (forwardQuery && myClientIds) forwardQuery = forwardQuery.in('client_id', myClientIds);

	// Part WC4.5: Website Chat is the fourth merged source, in the same keyset shape as the other three.
	// A resolved session's messages carry the denormalized client_id, so they ride
	// website_chat_messages_organization_client_idx the way the intents ride their own -- the explicit
	// "client_id is not null" is what keeps that partial index eligible when no single client is asked for.
	let chatQuery = includeInbound
		? ownerClient
				.from('website_chat_messages')
				.select(WEBSITE_CHAT_MESSAGE_COLUMNS)
				.eq('organization_id', organizationId)
				.not('client_id', 'is', null)
				.order('created_at', { ascending: false })
				.order('id', { ascending: false })
		: null;
	if (chatQuery && requestedClientId) chatQuery = chatQuery.eq('client_id', requestedClientId);
	// A chat message has no subject and no address of its own, so its body is the only text a search can
	// match. Same unindexed-ilike cost profile as the three sources above, no new pattern.
	if (chatQuery && search) chatQuery = chatQuery.ilike('body', `%${escapeSearch(search)}%`);
	if (chatQuery && cursor) {
		chatQuery = chatQuery
			.lte('created_at', cursor.createdAt)
			.or(
				`created_at.lt.${cursor.createdAt},and(created_at.eq.${cursor.createdAt},id.lt.${cursor.id})`
			);
	}
	if (chatQuery && myClientIds) chatQuery = chatQuery.in('client_id', myClientIds);

	// The needs-review half. organization_id is in the predicate for the index, not for safety -- the
	// sessions were already scoped above -- because website_chat_messages_session_timeline_idx leads with
	// organization_id and session ids alone cannot drive it. Without it this reads the whole table
	// (measured in 20260906090100_website_chat_wc45_staff_command_performance.sql).
	let reviewChatQuery = reviewSessionIds.length
		? ownerClient
				.from('website_chat_messages')
				.select(WEBSITE_CHAT_MESSAGE_COLUMNS)
				.eq('organization_id', organizationId)
				.in('session_id', reviewSessionIds)
				.is('client_id', null)
				.order('created_at', { ascending: false })
				.order('id', { ascending: false })
		: null;
	if (reviewChatQuery && search)
		reviewChatQuery = reviewChatQuery.ilike('body', `%${escapeSearch(search)}%`);
	if (reviewChatQuery && cursor) {
		reviewChatQuery = reviewChatQuery
			.lte('created_at', cursor.createdAt)
			.or(
				`created_at.lt.${cursor.createdAt},and(created_at.eq.${cursor.createdAt},id.lt.${cursor.id})`
			);
	}

	const [outboundResult, inboundResult, forwardResult, chatResult, reviewChatResult] =
		await Promise.all([
			outboundQuery.limit(fetchLimit),
			inboundQuery ? inboundQuery.limit(fetchLimit) : Promise.resolve({ data: [], error: null }),
			forwardQuery ? forwardQuery.limit(fetchLimit) : Promise.resolve({ data: [], error: null }),
			chatQuery ? chatQuery.limit(fetchLimit) : Promise.resolve({ data: [], error: null }),
			reviewChatQuery
				? reviewChatQuery.limit(fetchLimit)
				: Promise.resolve({ data: [], error: null })
		]);
	if (
		outboundResult.error ||
		inboundResult.error ||
		forwardResult.error ||
		chatResult.error ||
		reviewChatResult.error
	) {
		console.error(
			'Could not load Communications history.',
			outboundResult.error ??
				inboundResult.error ??
				forwardResult.error ??
				chatResult.error ??
				reviewChatResult.error
		);
		return databaseError();
	}
	const outboundRows = outboundResult.data ?? [];
	const inboundRows = inboundResult.data ?? [];
	const forwardRows = forwardResult.data ?? [];
	// Resolved and needs-review chat messages are one channel read two ways, never two channels.
	const chatRows = [...(chatResult.data ?? []), ...(reviewChatResult.data ?? [])];

	const combined = [
		...outboundRows.map((row) => ({ ...row, direction: 'outbound' as const })),
		...inboundRows.map((row) => ({ ...row, direction: 'inbound' as const })),
		...forwardRows.map((row) => ({ ...row, direction: 'forward' as const })),
		...chatRows.map((row) => ({ ...row, direction: 'website_chat' as const }))
	].sort((a, b) => b.created_at.localeCompare(a.created_at) || b.id.localeCompare(a.id));
	const extended = combined.slice(0, fetchLimit);
	const page = extended.slice(0, pageSize);
	const hasMore = extended.length > pageSize;

	const outboundPage = page.filter((row) => row.direction === 'outbound');
	const inboundPage = page.filter((row) => row.direction === 'inbound');
	const forwardPage = page.filter((row) => row.direction === 'forward');
	// Selected by id rather than by the tag so the chat rows keep their own row type instead of the merged
	// union, which has no session_id or sender_type.
	const chatPageIds = new Set(
		page.filter((row) => row.direction === 'website_chat').map((row) => row.id)
	);
	const chatPage = chatRows.filter((row) => chatPageIds.has(row.id));
	const chatSessionIds = [...new Set(chatPage.map((row) => row.session_id))];
	const clientIds = [...new Set(page.map((row) => row.client_id).filter((id) => id !== null))];
	const createdByIds = [
		...new Set(
			[
				...[...outboundPage, ...forwardPage].map((row) => row.created_by),
				...chatPage.map((row) => row.sender_user_id)
			].filter((id) => id !== null)
		)
	];
	const outboundIds = outboundPage.map((row) => row.id);
	const inboundIds = inboundPage.map((row) => row.id);
	// Only a 'failed' or 'cancelled' row can ever be resendable, so this stays a small, filtered lookup
	// even on a full page of otherwise-settled messages.
	const resendCandidateIds = outboundPage
		.filter((row) => row.status === 'failed' || row.status === 'cancelled')
		.map((row) => row.id);
	const [
		clientsResult,
		outboxResult,
		resentIntoResult,
		attachmentsResult,
		outboundAttachmentsResult,
		readMarksResult,
		assignmentsResult,
		myFollowsResult,
		chatSessionsResult
	] = await Promise.all([
		clientIds.length
			? ownerClient
					.from('clients')
					.select('id, display_name')
					.eq('organization_id', organizationId)
					.in('id', clientIds)
			: Promise.resolve({ data: [], error: null }),
		resendCandidateIds.length
			? ownerClient
					.from('communication_outbox_events')
					.select('delivery_intent_id, available_at')
					.in('delivery_intent_id', resendCandidateIds)
			: Promise.resolve({ data: [], error: null }),
		// A resend links forward from the new attempt back to the one it replaces, so the only way to find
		// the newer attempt from the original is to search for it — same-organization by construction (see
		// 20260825091500_communications_email_resend.sql), scoped again here defensively.
		outboundIds.length
			? ownerClient
					.from('communication_delivery_intents')
					.select('id, resent_from_intent_id, created_at')
					.eq('organization_id', organizationId)
					.in('resent_from_intent_id', outboundIds)
			: Promise.resolve({ data: [], error: null }),
		inboundIds.length
			? ownerClient
					.from('communication_inbound_attachments')
					.select('id, inbound_message_id, file_name, mime_type, byte_size, status, failure_reason')
					.in('inbound_message_id', inboundIds)
			: Promise.resolve({ data: [], error: null }),
		// Outbound has no status ladder (20260825170000_communications_outbound_attachments.sql) -- a row
		// here exists only for a file that already sent successfully, so there is nothing to filter on.
		outboundIds.length
			? ownerClient
					.from('communication_outbound_attachments')
					.select('id, delivery_intent_id, file_name, mime_type, byte_size')
					.in('delivery_intent_id', outboundIds)
			: Promise.resolve({ data: [], error: null }),
		(inboundIds.length || chatPage.length) && clientIds.length
			? ownerClient
					.from('communication_conversation_read_marks')
					.select('client_id, last_read_at')
					.eq('organization_id', organizationId)
					.eq('user_id', auth.user.id)
					.in('client_id', clientIds)
			: Promise.resolve({ data: [], error: null }),
		clientIds.length
			? ownerClient
					.from('communication_conversation_assignments')
					.select('client_id, assigned_to')
					.eq('organization_id', organizationId)
					.in('client_id', clientIds)
			: Promise.resolve({ data: [], error: null }),
		// Only the caller's own follow state is needed to render a Follow/Following toggle -- the full
		// follower list belongs to Part 5D's work-context panel, not this list/timeline read.
		clientIds.length
			? ownerClient
					.from('communication_conversation_followers')
					.select('client_id')
					.eq('organization_id', organizationId)
					.eq('user_id', auth.user.id)
					.in('client_id', clientIds)
			: Promise.resolve({ data: [], error: null }),
		// One row per chat conversation on the page, not per message: the ended state ("ended - who -
		// when"), the visitor's own name for a session that has no contact yet, and the two candidates a
		// needs-review session is caught between all live on the session, never on the message.
		chatSessionIds.length
			? ownerClient
					.from('website_chat_sessions')
					.select(
						'id, client_id, match_status, visitor_name, submitted_email, submitted_phone_e164, candidate_client_id_by_phone, candidate_client_id_by_email, started_at, last_activity_at, closed_at, closed_reason, closed_by'
					)
					.eq('organization_id', organizationId)
					.in('id', chatSessionIds)
			: Promise.resolve({ data: [], error: null })
	]);
	if (
		clientsResult.error ||
		outboxResult.error ||
		resentIntoResult.error ||
		attachmentsResult.error ||
		outboundAttachmentsResult.error ||
		readMarksResult.error ||
		assignmentsResult.error ||
		myFollowsResult.error ||
		chatSessionsResult.error
	) {
		return databaseError();
	}
	const chatSessions = chatSessionsResult.data ?? [];
	const namesById = new Map(
		(clientsResult.data ?? []).map((client) => [client.id, client.display_name])
	);
	const outboxByIntent = new Map(
		(outboxResult.data ?? []).map((row) => [row.delivery_intent_id, row.available_at])
	);
	const assignedToByClient = new Map(
		(assignmentsResult.data ?? []).map((row) => [row.client_id, row.assigned_to])
	);
	const followingClientIds = new Set((myFollowsResult.data ?? []).map((row) => row.client_id));

	// Whoever ended a session, and the two candidate Clients a needs-review session is caught between.
	// Neither can be known before the sessions above come back, so both ride the profile lookup that was
	// already going to run rather than adding a wave of their own.
	const closedByIds = chatSessions.map((row) => row.closed_by).filter((id) => id !== null);
	const candidateClientIds = [
		...new Set(
			chatSessions
				.flatMap((row) => [row.candidate_client_id_by_phone, row.candidate_client_id_by_email])
				.filter((id): id is string => id !== null && !namesById.has(id))
		)
	];
	const profileIds = [
		...new Set([...createdByIds, ...assignedToByClient.values(), ...closedByIds])
	];
	const [profilesResult, candidateClientsResult] = await Promise.all([
		profileIds.length
			? ownerClient.from('profiles').select('id, full_name').in('id', profileIds)
			: Promise.resolve({ data: [], error: null }),
		candidateClientIds.length
			? ownerClient
					.from('clients')
					.select('id, display_name')
					.eq('organization_id', organizationId)
					.in('id', candidateClientIds)
			: Promise.resolve({ data: [], error: null })
	]);
	if (profilesResult.error || candidateClientsResult.error) return databaseError();
	for (const client of candidateClientsResult.data ?? []) {
		namesById.set(client.id, client.display_name);
	}
	const profileNameById = new Map(
		(profilesResult.data ?? []).map((profile) => [profile.id, profile.full_name])
	);
	const resentIntoByOriginal = new Map<string, string>();
	for (const row of resentIntoResult.data ?? []) {
		if (!row.resent_from_intent_id) continue;
		const existing = resentIntoByOriginal.get(row.resent_from_intent_id);
		if (!existing) {
			resentIntoByOriginal.set(row.resent_from_intent_id, row.id);
			continue;
		}
		// Guard logic should keep this to one live resend per original, but pick the newest if data ever
		// disagrees rather than picking arbitrarily.
		const existingRow = (resentIntoResult.data ?? []).find(
			(candidate) => candidate.id === existing
		);
		if (existingRow && row.created_at > existingRow.created_at) {
			resentIntoByOriginal.set(row.resent_from_intent_id, row.id);
		}
	}
	const canResend = (row: { id: string; status: string }) => {
		// A message that already has a newer attempt is settled by that attempt, not by resending the
		// original again — otherwise two live retries could both reach the same customer.
		if (resentIntoByOriginal.has(row.id)) return false;
		if (row.status === 'cancelled') return true;
		if (row.status !== 'failed') return false;
		const availableAt = outboxByIntent.get(row.id);
		return availableAt === undefined || availableAt === 'infinity';
	};
	const attachmentsByMessage = new Map<string, (typeof attachmentsResult.data)[number][]>();
	for (const attachment of attachmentsResult.data ?? []) {
		const list = attachmentsByMessage.get(attachment.inbound_message_id) ?? [];
		list.push(attachment);
		attachmentsByMessage.set(attachment.inbound_message_id, list);
	}
	const outboundAttachmentsByMessage = new Map<
		string,
		(typeof outboundAttachmentsResult.data)[number][]
	>();
	for (const attachment of outboundAttachmentsResult.data ?? []) {
		const list = outboundAttachmentsByMessage.get(attachment.delivery_intent_id) ?? [];
		list.push(attachment);
		outboundAttachmentsByMessage.set(attachment.delivery_intent_id, list);
	}
	const lastReadAtByClient = new Map(
		(readMarksResult.data ?? []).map((row) => [row.client_id, row.last_read_at])
	);
	// A guarded/unresolved-sender message has no client_id, so it is never assigned, followed, or named --
	// Part 5C's forward/attach flow is the only path that gives one a contact identity.
	const conversationOwnership = (clientId: string | null) => {
		if (!clientId) return { assigned_to: null, assigned_to_name: null, is_following: false };
		const assignedTo = assignedToByClient.get(clientId) ?? null;
		return {
			assigned_to: assignedTo,
			assigned_to_name: assignedTo ? (profileNameById.get(assignedTo) ?? null) : null,
			is_following: followingClientIds.has(clientId)
		};
	};

	const outboundMessages = outboundPage.map(({ direction: _direction, ...row }) => ({
		...row,
		client_name: namesById.get(row.client_id) ?? 'Client unavailable',
		client_email: row.recipient_email,
		attachments: outboundAttachmentsByMessage.get(row.id) ?? [],
		can_resend: canResend(row),
		created_by_name:
			row.send_kind === 'manual'
				? row.created_by
					? (profileNameById.get(row.created_by) ?? null)
					: null
				: null,
		resent_into_intent_id: resentIntoByOriginal.get(row.id) ?? null,
		...conversationOwnership(row.client_id)
	}));
	const inboundMessages = inboundPage.map(({ direction: _direction, ...row }) => {
		const lastReadAt = row.client_id ? (lastReadAtByClient.get(row.client_id) ?? null) : null;
		return {
			...row,
			client_name: row.client_id ? (namesById.get(row.client_id) ?? 'Client unavailable') : null,
			attachments: attachmentsByMessage.get(row.id) ?? [],
			unread: !lastReadAt || row.created_at > lastReadAt,
			...conversationOwnership(row.client_id)
		};
	});
	// A forward reuses the outbound status vocabulary (see outboundEmailStatus in $lib/communications/
	// inbox), so it needs no new status mapping. It carries no quote/resend chain and, per docs/contractor-
	// email-contract.md § Recipients, forwarding, and portal access, is never the authoritative attachment
	// surface -- the original inbound message's own row is -- so it never lists its own attachments here.
	// client_email is deliberately left blank rather than the external forward target: it is never the
	// customer's own address, and conversationCustomerEmail ($lib/communications/inbox) already skips a
	// forward row when deriving "who a reply goes to."
	const forwardMessages = forwardPage.map(({ direction: _direction, ...row }) => ({
		...row,
		client_name: namesById.get(row.client_id) ?? 'Client unavailable',
		client_email: '',
		quote_id: null,
		resent_from_intent_id: null,
		resent_into_intent_id: null,
		// A forward has no provider delivery-outcome axis of its own (Part 7.1).
		delivery_outcome: null,
		delivery_outcome_at: null,
		attachments: [],
		can_resend: false,
		send_kind: 'forward',
		created_by_name: row.created_by ? (profileNameById.get(row.created_by) ?? null) : null,
		...conversationOwnership(row.client_id)
	}));

	// Direction is derived rather than read (see chatDirection). Unread reuses the contact's own read
	// mark, so a chat and an email in the same conversation clear together -- and an unresolved session,
	// having no contact and therefore no read-mark seam, never clears at all, exactly like a guarded
	// inbound email. The two chat reads are concatenated, so this page is sorted once here.
	const chatMessages = chatPage
		.map((row) => {
			const direction = chatDirection(row.sender_type);
			const lastReadAt = row.client_id ? (lastReadAtByClient.get(row.client_id) ?? null) : null;
			return {
				...row,
				channel: 'website_chat' as const,
				direction,
				client_name: row.client_id ? (namesById.get(row.client_id) ?? 'Client unavailable') : null,
				sender_name: row.sender_user_id ? (profileNameById.get(row.sender_user_id) ?? null) : null,
				unread: direction === 'inbound' && (!lastReadAt || row.created_at > lastReadAt),
				...conversationOwnership(row.client_id)
			};
		})
		.sort((a, b) => b.created_at.localeCompare(a.created_at) || b.id.localeCompare(a.id));

	const websiteChatSessions = chatSessions.map((row) => ({
		id: row.id,
		client_id: row.client_id,
		client_name: row.client_id ? (namesById.get(row.client_id) ?? 'Client unavailable') : null,
		match_status: row.match_status,
		visitor_name: row.visitor_name,
		visitor_email: row.submitted_email,
		visitor_phone: row.submitted_phone_e164,
		started_at: row.started_at,
		last_activity_at: row.last_activity_at,
		closed_at: row.closed_at,
		closed_reason: row.closed_reason,
		closed_by: row.closed_by,
		closed_by_name: row.closed_by ? (profileNameById.get(row.closed_by) ?? null) : null,
		// Only a needs-review session has these, and they are what the resolve dialog offers as its two
		// suggestions. UCRM never picks between them -- a person does.
		candidates: [
			{ matched_on: 'phone' as const, client_id: row.candidate_client_id_by_phone },
			{ matched_on: 'email' as const, client_id: row.candidate_client_id_by_email }
		]
			.filter((candidate): candidate is { matched_on: 'phone' | 'email'; client_id: string } =>
				Boolean(candidate.client_id)
			)
			.map((candidate) => ({
				...candidate,
				client_name: namesById.get(candidate.client_id) ?? 'Client unavailable'
			}))
	}));

	const last = extended.at(pageSize - 1);
	const response: Record<string, unknown> = {
		emails: outboundMessages,
		next_cursor: hasMore && last ? `${last.created_at}|${last.id}` : null,
		view,
		can_view_team: canViewTeam,
		can_manage_assignment: canManageAssignment,
		can_forward: canForward,
		can_send: canSend
	};
	if (includeInbound) {
		// Website Chat travels beside `messages` rather than inside it. The merge that governs paging
		// already happened -- chat rows took page slots and drove the cursor above -- so this only decides
		// where they are handed over, and a separate array leaves the email-shaped union every shipped
		// screen already reads exactly as it is. WC4.5 Layer 3 interleaves the two in the timeline.
		response.website_chat = chatMessages;
		response.website_chat_sessions = websiteChatSessions;
		response.messages = [
			...outboundMessages.map((row) => ({ ...row, direction: 'outbound' as const })),
			...inboundMessages.map((row) => ({ ...row, direction: 'inbound' as const })),
			...forwardMessages.map((row) => ({ ...row, direction: 'outbound' as const }))
		].sort((a, b) => b.created_at.localeCompare(a.created_at) || b.id.localeCompare(a.id));
	}

	return json(response, { headers: PRIVATE_READ_HEADERS });
};
