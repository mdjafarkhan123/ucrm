import { createBrowserClient } from '@supabase/ssr';
import type { Database } from '$lib/database.types';
import { getPublicEnv } from '$lib/config/public';

const publicEnv = getPublicEnv();

export const supabase = createBrowserClient<Database>(
	publicEnv.PUBLIC_SUPABASE_URL,
	publicEnv.PUBLIC_SUPABASE_PUBLISHABLE_KEY
);
