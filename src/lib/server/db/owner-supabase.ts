import { createClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { getPublicEnv } from '$lib/config/public';
import { getServerEnv } from '$lib/server/env';

const publicEnv = getPublicEnv();

export function getOwnerSupabaseClient() {
	const { SUPABASE_SERVICE_ROLE_KEY: serviceRoleKey } = getServerEnv();

	return createClient<Database>(publicEnv.PUBLIC_SUPABASE_URL, serviceRoleKey, {
		auth: { autoRefreshToken: false, persistSession: false }
	});
}
