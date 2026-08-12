import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { getServerEnv } from '$lib/server/env';

const settingsSelect =
	'privacy_policy_url, privacy_policy_version, payment_instructions, sender_display_name, reply_to_address, alert_recipient_emails, updated_at';

/**
 * The singleton row is created lazily on first read, seeded with the configured owner
 * login email as the initial alert recipient. `ignoreDuplicates` makes concurrent first
 * reads safe -- whichever request's insert loses the race is a no-op, and both then read
 * back the same row instead of one silently overwriting the other's seed values.
 */
export async function getOrCreateOwnerSettings(client: SupabaseClient<Database>) {
	const { SUPER_ADMIN_EMAIL } = getServerEnv();

	const { error: upsertError } = await client
		.from('platform_owner_settings')
		.upsert(
			{ id: true, alert_recipient_emails: [SUPER_ADMIN_EMAIL] },
			{ onConflict: 'id', ignoreDuplicates: true }
		);
	if (upsertError) throw upsertError;

	const { data, error } = await client
		.from('platform_owner_settings')
		.select(settingsSelect)
		.eq('id', true)
		.single();
	if (error) throw error;

	return data;
}
