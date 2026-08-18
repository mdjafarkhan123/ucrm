import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';

// Calendar statuses only make sense in the contractor's own timezone, so every request read needs this
// value. It is one row per organization and it almost never changes, so it is held in process for a few
// minutes rather than fetched again for every user on every page. Tenant-global, never per user.
const CACHE_TTL_MS = 5 * 60 * 1000;
const cache = new Map<string, { timezone: string; expiresAt: number }>();

export function forgetOrganizationTimezone(organizationId: string) {
	cache.delete(organizationId);
}

export async function organizationTimezone(
	supabase: SupabaseClient<Database>,
	organizationId: string
) {
	const cached = cache.get(organizationId);
	if (cached && cached.expiresAt > Date.now()) return cached.timezone;

	const { data } = await supabase
		.from('organization_settings')
		.select('timezone')
		.eq('organization_id', organizationId)
		.maybeSingle();

	const timezone = data?.timezone ?? 'UTC';
	cache.set(organizationId, { timezone, expiresAt: Date.now() + CACHE_TTL_MS });
	return timezone;
}
