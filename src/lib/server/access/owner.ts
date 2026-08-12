import type { Json } from '$lib/database.types';
import { json } from '@sveltejs/kit';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';

export function ownerUnauthorized() {
	return json({ error: 'Platform owner authentication required.' }, { status: 401 });
}

export async function recordOwnerAccessAudit(
	client: SupabaseClient<Database>,
	input: {
		organization_id: string;
		email: string;
		event_type: string;
		target_type: string;
		target_key?: string | null;
		before_state?: Json | null;
		after_state?: Json | null;
	}
) {
	const { error } = await client.from('access_audit_events').insert({
		organization_id: input.organization_id,
		actor_kind: 'platform_owner',
		actor_owner_email: input.email,
		event_type: input.event_type,
		target_type: input.target_type,
		target_key: input.target_key ?? null,
		before_state: input.before_state ?? null,
		after_state: input.after_state ?? null
	});
	if (error) throw error;
}
