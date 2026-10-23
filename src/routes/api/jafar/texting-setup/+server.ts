import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Stage 10 Part 5b: the Texting setup page. Every country a business asked for that still waits on Uplift,
// oldest first, and the page's four numbers. Read-only; the task's buttons post to the routes below.
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	try {
		const { data, error } = await getOwnerSupabaseClient().rpc('communication_sms_destination_queue');
		if (error) throw error;
		return json(data, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not load the texting setup queue.', error);
		return json({ error: 'The to-do list could not be loaded.' }, { status: 500 });
	}
};
