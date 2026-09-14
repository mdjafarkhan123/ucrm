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

// The audit trail for a Platform Owner action that has no single owning organization -- a platform-wide SMS
// hold, a published retail rate. access_audit_events keeps organization_id NOT NULL by design (Stage 2C-5c
// decision, see Memory/campaigns/communications-activation/NOW.md), so a platform-scoped action records here
// instead, never by loosening that constraint.
export async function recordPlatformAudit(
	client: SupabaseClient<Database>,
	input: {
		email: string;
		event_type: string;
		target_type: string;
		target_key?: string | null;
		before_state?: Json | null;
		after_state?: Json | null;
	}
) {
	const { error } = await client.from('platform_audit_events').insert({
		actor_owner_email: input.email,
		event_type: input.event_type,
		target_type: input.target_type,
		target_key: input.target_key ?? null,
		before_state: input.before_state ?? null,
		after_state: input.after_state ?? null
	});
	if (error) throw error;
}
