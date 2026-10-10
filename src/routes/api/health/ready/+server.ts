import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Readiness: the app can also reach its database. The release step calls this after a deploy before trusting
// the new image. It is a separate route from /api/health so a database blip fails a release check without
// restarting a healthy container. The answer carries no error text or configuration.
export const GET: RequestHandler = async () => {
	const headers = { 'cache-control': 'no-store' };
	try {
		const { error } = await getOwnerSupabaseClient()
			.from('platform_rate_limit_buckets')
			.select('bucket_key')
			.limit(1);
		if (error) throw error;
		return json({ status: 'ready' }, { headers });
	} catch (error) {
		console.error('Readiness check failed.', error);
		return json({ status: 'unavailable' }, { status: 503, headers });
	}
};
