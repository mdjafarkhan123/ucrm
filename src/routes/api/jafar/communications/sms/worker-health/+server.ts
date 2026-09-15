import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Stage 4C: the lean SMS-worker health read for the Jafar Communications control room. Mirrors
// email-health's worker_health piece; SMS has no platform-pause state of its own here (that already lives
// on /api/jafar/communications/sms/platform-holds), so this route stays worker-only.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	try {
		const client = getOwnerSupabaseClient();
		const { data, error } = await client.rpc('get_communication_sms_worker_health');
		if (error) throw error;
		return json({ worker_health: data }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not load SMS worker health.', error);
		return json({ error: 'SMS worker health could not be loaded.' }, { status: 500 });
	}
};
