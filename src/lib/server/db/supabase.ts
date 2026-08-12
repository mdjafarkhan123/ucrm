import { createClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { getPublicEnv } from '$lib/config/public';

const publicEnv = getPublicEnv();

export const createPublicSupabaseClient = () =>
	createClient<Database>(publicEnv.PUBLIC_SUPABASE_URL, publicEnv.PUBLIC_SUPABASE_PUBLISHABLE_KEY);
