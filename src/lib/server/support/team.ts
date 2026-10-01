import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import type { SupportSenderKind, SupportTeamThread } from '$lib/support/api';

// The conversations a member sees beyond their own (D3): ones they were added to and, for owners and
// admins, every conversation in the organization. Row level security decides which rows come back; these
// reads only shape them. A team is tens of people, so its conversations fit in one capped read.
const MAX_TEAM_THREADS = 200;

// "Someone else's": started by another member, or by one whose account has since gone.
const notStartedBy = (userId: string) =>
	`started_by_user_id.is.null,started_by_user_id.neq.${userId}`;

export async function countTeamThreads(
	client: SupabaseClient<Database>,
	organizationId: string,
	userId: string
): Promise<number | null> {
	const { count, error } = await client
		.from('support_threads')
		.select('id', { count: 'exact', head: true })
		.eq('organization_id', organizationId)
		.or(notStartedBy(userId));
	return error ? null : (count ?? 0);
}

/** A member's name as their teammates see it. Someone no longer on the team is not readable here. */
export async function teammateNames(client: SupabaseClient<Database>, ids: string[]) {
	if (ids.length === 0) return new Map<string, string>();
	const { data, error } = await client.from('profiles').select('id, full_name').in('id', ids);
	if (error) throw error;
	return new Map(
		data.flatMap((profile) => (profile.full_name ? [[profile.id, profile.full_name] as const] : []))
	);
}

export const FORMER_MEMBER = 'Former team member';

export async function readTeamThreads(
	client: SupabaseClient<Database>,
	organizationId: string,
	userId: string
): Promise<SupportTeamThread[]> {
	const { data: threads, error } = await client
		.from('support_threads')
		.select(
			'id, started_by_user_id, last_message_at, last_message_preview, last_message_sender_kind'
		)
		.eq('organization_id', organizationId)
		.or(notStartedBy(userId))
		.order('last_message_at', { ascending: false })
		.order('id', { ascending: false })
		.limit(MAX_TEAM_THREADS);
	if (error) throw error;
	if (threads.length === 0) return [];

	const ids = threads.map((thread) => thread.id);
	const starters = [...new Set(threads.flatMap((thread) => thread.started_by_user_id ?? []))];
	const [marks, added, names] = await Promise.all([
		client
			.from('support_thread_reads')
			.select('thread_id, last_read_at')
			.eq('user_id', userId)
			.in('thread_id', ids),
		client
			.from('support_thread_participants')
			.select('thread_id')
			.eq('user_id', userId)
			.in('thread_id', ids),
		teammateNames(client, starters)
	]);
	if (marks.error) throw marks.error;
	if (added.error) throw added.error;

	const markById = new Map(marks.data.map((mark) => [mark.thread_id, mark.last_read_at]));
	const addedIds = new Set(added.data.map((row) => row.thread_id));
	return threads.map((thread) => {
		const mark = markById.get(thread.id);
		return {
			id: thread.id,
			started_by_name:
				(thread.started_by_user_id && names.get(thread.started_by_user_id)) || FORMER_MEMBER,
			last_message_at: thread.last_message_at,
			last_message_preview: thread.last_message_preview,
			last_message_sender_kind: thread.last_message_sender_kind as SupportSenderKind,
			unread: !mark || Date.parse(thread.last_message_at) > Date.parse(mark),
			added: addedIds.has(thread.id)
		};
	});
}
