import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import type {
	SupportInboxThread,
	SupportSenderKind,
	SupportSettings,
	SupportTopic
} from '$lib/support/api';

// The Support Inbox reads with the platform owner's service-role client, after the route has proved the
// owner's session. Nothing here is reachable from a contractor's request.

const THREAD_SELECT =
	'id, topic, started_by_user_id, last_message_at, last_message_preview, last_message_sender_kind, uplift_last_read_at, organizations(id, name)';

type ThreadRow = {
	id: string;
	topic: string;
	started_by_user_id: string | null;
	last_message_at: string;
	last_message_preview: string;
	last_message_sender_kind: string;
	uplift_last_read_at: string | null;
	organizations: { id: string; name: string } | { id: string; name: string }[] | null;
};

// One read for every member's name on the page, rather than one per thread.
async function memberNames(client: SupabaseClient<Database>, rows: ThreadRow[]) {
	const ids = [...new Set(rows.map((row) => row.started_by_user_id).filter((id) => id !== null))];
	if (ids.length === 0) return new Map<string, string>();

	const { data, error } = await client.from('profiles').select('id, full_name').in('id', ids);
	if (error) throw error;
	return new Map(
		data.flatMap((profile) => (profile.full_name ? [[profile.id, profile.full_name] as const] : []))
	);
}

function toInboxThread(row: ThreadRow, names: Map<string, string>): SupportInboxThread | null {
	const organization = Array.isArray(row.organizations) ? row.organizations[0] : row.organizations;
	if (!organization) return null;
	return {
		id: row.id,
		topic: row.topic as SupportTopic,
		organization: { id: organization.id, name: organization.name },
		member_name: (row.started_by_user_id && names.get(row.started_by_user_id)) || 'Team member',
		last_message_at: row.last_message_at,
		last_message_preview: row.last_message_preview,
		last_message_sender_kind: row.last_message_sender_kind as SupportSenderKind,
		// The same test as public.support_inbox_unread_count: the contractor wrote last, after Uplift's mark.
		unread:
			row.last_message_sender_kind === 'member' &&
			(row.uplift_last_read_at === null ||
				Date.parse(row.last_message_at) > Date.parse(row.uplift_last_read_at))
	};
}

/**
 * Every organization's chats, newest activity first, optionally only one topic's (read on
 * support_threads_inbox_topic_idx). One extra row tells the caller whether more exist.
 */
export async function readSupportInbox(
	client: SupabaseClient<Database>,
	limit: number,
	topic: SupportTopic | undefined
) {
	let query = client.from('support_threads').select(THREAD_SELECT);
	if (topic) query = query.eq('topic', topic);
	const { data, error } = await query
		.order('last_message_at', { ascending: false })
		.order('id', { ascending: false })
		.limit(limit + 1);
	if (error) throw error;

	const rows = (data as ThreadRow[]).slice(0, limit);
	const names = await memberNames(client, rows);
	return {
		threads: rows.flatMap((row) => toInboxThread(row, names) ?? []),
		has_more: data.length > limit
	};
}

export async function readSupportInboxThread(client: SupabaseClient<Database>, threadId: string) {
	const { data, error } = await client
		.from('support_threads')
		.select(THREAD_SELECT)
		.eq('id', threadId)
		.maybeSingle();
	if (error) throw error;
	if (!data) return null;

	const row = data as ThreadRow;
	return toInboxThread(row, await memberNames(client, [row]));
}

export async function readSupportSettings(
	client: SupabaseClient<Database>
): Promise<SupportSettings> {
	const { data, error } = await client
		.from('platform_support_settings')
		.select('responder_name, availability_note')
		.eq('id', true)
		.maybeSingle();
	if (error) throw error;
	return {
		responder_name: data?.responder_name ?? '',
		availability_note: data?.availability_note ?? ''
	};
}
