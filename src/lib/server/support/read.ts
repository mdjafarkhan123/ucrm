import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import type { SupportMessage, SupportSenderKind } from '$lib/support/api';

// A message's files ride along in the same read: at most 5 each, found by their message.
const MESSAGE_SELECT =
	'id, sender_kind, sender_user_id, sender_name, body, created_at, attachments:support_message_attachments(id, file_name, mime_type, byte_size, has_thumbnail, position)';

// The latest `limit` messages of one thread, returned oldest first. One extra row is asked for so the
// caller knows whether earlier messages exist without counting the whole thread.
export async function readSupportMessages(
	client: SupabaseClient<Database>,
	threadId: string,
	limit: number
): Promise<{ messages: SupportMessage[]; has_earlier: boolean } | null> {
	const { data, error } = await client
		.from('support_messages')
		.select(MESSAGE_SELECT)
		.eq('thread_id', threadId)
		.order('created_at', { ascending: false })
		.order('id', { ascending: false })
		.limit(limit + 1);
	if (error) return null;

	const messages = data
		.slice(0, limit)
		.reverse()
		.map((row) => ({
			...row,
			sender_kind: row.sender_kind as SupportSenderKind,
			attachments: [...(row.attachments ?? [])]
				.sort((first, second) => first.position - second.position)
				.map(({ id, file_name, mime_type, byte_size, has_thumbnail }) => ({
					id,
					file_name,
					mime_type,
					byte_size,
					has_thumbnail
				}))
		}));
	return { messages, has_earlier: data.length > limit };
}
