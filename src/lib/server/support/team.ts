import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import type {
	SupportChatRow,
	SupportSenderKind,
	SupportStatus,
	SupportTopic
} from '$lib/support/api';

// The chats a member sees in the messenger: their own (D4a: one per question), and someone else's they were
// added to or, for owners and admins, administer (D3). Row level security decides which rows come back;
// these reads only shape them. Each list is capped: a team is tens of people, and a member's own chats are
// read newest first on support_threads_member_chats_idx.
const MAX_OWN_CHATS = 100;
const MAX_TEAM_CHATS = 200;

const CHAT_SELECT =
	'id, topic, started_by_user_id, last_message_at, last_message_preview, last_message_sender_kind, status';

type ChatRow = {
	id: string;
	topic: string;
	started_by_user_id: string | null;
	last_message_at: string;
	last_message_preview: string;
	last_message_sender_kind: string;
	status: string;
};

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

export async function readChats(
	client: SupabaseClient<Database>,
	organizationId: string,
	userId: string
): Promise<{ mine: SupportChatRow[]; team: SupportChatRow[] }> {
	const [own, others] = await Promise.all([
		client
			.from('support_threads')
			.select(CHAT_SELECT)
			.eq('organization_id', organizationId)
			.eq('started_by_user_id', userId)
			.order('last_message_at', { ascending: false })
			.order('id', { ascending: false })
			.limit(MAX_OWN_CHATS),
		// "Someone else's": started by another member, or by one whose account has since gone.
		client
			.from('support_threads')
			.select(CHAT_SELECT)
			.eq('organization_id', organizationId)
			.or(`started_by_user_id.is.null,started_by_user_id.neq.${userId}`)
			.order('last_message_at', { ascending: false })
			.order('id', { ascending: false })
			.limit(MAX_TEAM_CHATS)
	]);
	if (own.error) throw own.error;
	if (others.error) throw others.error;

	const rows: ChatRow[] = [...own.data, ...others.data];
	if (rows.length === 0) return { mine: [], team: [] };

	const ids = rows.map((row) => row.id);
	const starters = [...new Set(rows.flatMap((row) => row.started_by_user_id ?? []))];
	const [marks, added, names] = await Promise.all([
		client
			.from('support_thread_reads')
			.select('thread_id, last_read_at')
			.eq('user_id', userId)
			.in('thread_id', ids),
		others.data.length === 0
			? Promise.resolve({ data: [], error: null })
			: client
					.from('support_thread_participants')
					.select('thread_id')
					.eq('user_id', userId)
					.in(
						'thread_id',
						others.data.map((row) => row.id)
					),
		teammateNames(client, starters)
	]);
	if (marks.error) throw marks.error;
	if (added.error) throw added.error;

	const markById = new Map(marks.data.map((mark) => [mark.thread_id, mark.last_read_at]));
	const addedIds = new Set(added.data.map((row) => row.thread_id));
	const toRow = (row: ChatRow): SupportChatRow => {
		const mark = markById.get(row.id);
		return {
			id: row.id,
			topic: row.topic as SupportTopic,
			started_by_name:
				(row.started_by_user_id && names.get(row.started_by_user_id)) || FORMER_MEMBER,
			last_message_at: row.last_message_at,
			last_message_preview: row.last_message_preview,
			last_message_sender_kind: row.last_message_sender_kind as SupportSenderKind,
			// The member's own message moves their mark, and system lines never move the latest time.
			unread: !mark || Date.parse(row.last_message_at) > Date.parse(mark),
			added: addedIds.has(row.id),
			status: row.status as SupportStatus
		};
	};
	return { mine: own.data.map(toRow), team: others.data.map(toRow) };
}
