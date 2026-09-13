import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import type { CoreSearchResult } from './core-records';

const SOURCE_LIMIT = 5;
const GROUP_LIMIT = 5;

export type ConversationSearchScope = {
	canViewTeam: boolean;
	canViewAssigned: boolean;
	userId: string;
};

type Match = {
	id: string;
	organizationId: string;
	clientId: string | null;
	conversationKey: string;
	createdAt: string;
	channel: 'Email' | 'Website Chat';
	headline: string;
	fallbackName: string | null;
	sessionId: string | null;
};

function likeTerm(term: string) {
	return `%${term.replace(/[\\%_]/g, (character) => `\\${character}`)}%`;
}

function orTerm(term: string) {
	return `"${likeTerm(term).replace(/"/g, '\\"')}"`;
}

function searchHref(term: string, conversationKey: string) {
	const params = new URLSearchParams({ search: term, conversation: conversationKey });
	return `/communications?${params.toString()}`;
}

export async function searchConversations(
	supabase: SupabaseClient<Database>,
	organizationId: string,
	term: string,
	scope: ConversationSearchScope
): Promise<CoreSearchResult[]> {
	if (!scope.canViewTeam && !scope.canViewAssigned) return [];

	let visibleClientIds: string[] | null = null;
	if (!scope.canViewTeam) {
		const [assigned, followed] = await Promise.all([
			supabase
				.from('communication_conversation_assignments')
				.select('client_id')
				.eq('organization_id', organizationId)
				.eq('assigned_to', scope.userId),
			supabase
				.from('communication_conversation_followers')
				.select('client_id')
				.eq('organization_id', organizationId)
				.eq('user_id', scope.userId)
		]);
		if (assigned.error) throw assigned.error;
		if (followed.error) throw followed.error;
		visibleClientIds = [
			...new Set([
				...(assigned.data ?? []).map((row) => row.client_id),
				...(followed.data ?? []).map((row) => row.client_id)
			])
		];
		if (visibleClientIds.length === 0) return [];
	}

	const quoted = orTerm(term);
	const pattern = likeTerm(term);
	let outbound = supabase
		.from('communication_delivery_intents')
		.select('id, organization_id, client_id, recipient_email, subject, created_at')
		.eq('organization_id', organizationId)
		.eq('channel', 'email')
		.or(`subject.ilike.${quoted},recipient_email.ilike.${quoted}`)
		.order('created_at', { ascending: false })
		.limit(SOURCE_LIMIT);
	let inbound = supabase
		.from('communication_inbound_messages')
		.select(
			'id, organization_id, client_id, sender_email, sender_name, subject, review_status, created_at'
		)
		.eq('organization_id', organizationId)
		.neq('review_status', 'dismissed')
		.or(`subject.ilike.${quoted},sender_email.ilike.${quoted},sender_name.ilike.${quoted}`)
		.order('created_at', { ascending: false })
		.limit(SOURCE_LIMIT);
	let forwarded = supabase
		.from('communication_forward_events')
		.select('id, organization_id, client_id, subject, created_at')
		.eq('organization_id', organizationId)
		.ilike('subject', pattern)
		.order('created_at', { ascending: false })
		.limit(SOURCE_LIMIT);
	let chat = supabase
		.from('website_chat_messages')
		.select('id, organization_id, client_id, session_id, body, created_at')
		.eq('organization_id', organizationId)
		.ilike('body', pattern)
		.order('created_at', { ascending: false })
		.limit(SOURCE_LIMIT);

	if (visibleClientIds) {
		outbound = outbound.in('client_id', visibleClientIds);
		inbound = inbound.in('client_id', visibleClientIds);
		forwarded = forwarded.in('client_id', visibleClientIds);
		chat = chat.in('client_id', visibleClientIds);
	}

	const [outboundResult, inboundResult, forwardedResult, chatResult] = await Promise.all([
		outbound,
		inbound,
		forwarded,
		chat
	]);
	if (outboundResult.error) throw outboundResult.error;
	if (inboundResult.error) throw inboundResult.error;
	if (forwardedResult.error) throw forwardedResult.error;
	if (chatResult.error) throw chatResult.error;

	const matches: Match[] = [
		...(outboundResult.data ?? []).map((row) => ({
			id: row.id,
			organizationId: row.organization_id,
			clientId: row.client_id,
			conversationKey: row.client_id,
			createdAt: row.created_at,
			channel: 'Email' as const,
			headline: row.subject ?? '',
			fallbackName: row.recipient_email,
			sessionId: null
		})),
		...(inboundResult.data ?? []).map((row) => ({
			id: row.id,
			organizationId: row.organization_id,
			clientId: row.client_id,
			conversationKey: row.client_id ?? `guarded:${row.sender_email}`,
			createdAt: row.created_at,
			channel: 'Email' as const,
			headline: row.subject,
			fallbackName: row.sender_name ?? row.sender_email,
			sessionId: null
		})),
		...(forwardedResult.data ?? []).map((row) => ({
			id: row.id,
			organizationId: row.organization_id,
			clientId: row.client_id,
			conversationKey: row.client_id,
			createdAt: row.created_at,
			channel: 'Email' as const,
			headline: row.subject,
			fallbackName: null,
			sessionId: null
		})),
		...(chatResult.data ?? []).map((row) => ({
			id: row.id,
			organizationId: row.organization_id,
			clientId: row.client_id,
			conversationKey: row.client_id ?? `webchat:${row.session_id}`,
			createdAt: row.created_at,
			channel: 'Website Chat' as const,
			headline: row.body,
			fallbackName: null,
			sessionId: row.session_id
		}))
	]
		.filter(
			(match) =>
				match.organizationId === organizationId &&
				(visibleClientIds === null ||
					(match.clientId !== null && visibleClientIds.includes(match.clientId)))
		)
		.sort((a, b) => b.createdAt.localeCompare(a.createdAt) || b.id.localeCompare(a.id));

	const newestByConversation = new Map<string, Match>();
	for (const match of matches) {
		if (!newestByConversation.has(match.conversationKey)) {
			newestByConversation.set(match.conversationKey, match);
		}
	}
	const selected = [...newestByConversation.values()].slice(0, GROUP_LIMIT);
	const clientIds = [
		...new Set(selected.map((match) => match.clientId).filter(Boolean))
	] as string[];
	const sessionIds = [
		...new Set(selected.map((match) => match.sessionId).filter(Boolean))
	] as string[];
	const [clients, sessions] = await Promise.all([
		clientIds.length
			? supabase
					.from('clients')
					.select('id, display_name')
					.eq('organization_id', organizationId)
					.in('id', clientIds)
			: Promise.resolve({ data: [], error: null }),
		sessionIds.length
			? supabase
					.from('website_chat_sessions')
					.select('id, visitor_name')
					.eq('organization_id', organizationId)
					.in('id', sessionIds)
			: Promise.resolve({ data: [], error: null })
	]);
	if (clients.error) throw clients.error;
	if (sessions.error) throw sessions.error;
	const clientNames = new Map((clients.data ?? []).map((row) => [row.id, row.display_name]));
	const visitorNames = new Map((sessions.data ?? []).map((row) => [row.id, row.visitor_name]));

	return selected.map((match) => ({
		id: match.conversationKey,
		type: 'conversation',
		title:
			(match.clientId ? clientNames.get(match.clientId) : null) ??
			(match.sessionId ? visitorNames.get(match.sessionId) : null) ??
			match.fallbackName ??
			'Conversation',
		subtitle: `${match.channel} · ${match.headline}`,
		href: searchHref(term, match.conversationKey)
	}));
}
