import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { withOptOutTasks } from '$lib/server/communications/sms-opt-out-tasks';

// Stage 10 Part 5b: the Texting setup page. Every country a business asked for that still waits on Uplift,
// oldest first, the opt-out words they need (Part 5d), and the page's four numbers. Read-only; the task's buttons post to the routes below.
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	try {
		const client = getOwnerSupabaseClient();
		const { data, error } = await client.rpc('communication_sms_destination_queue');
		if (error) throw error;
		const queue = await withOptOutTasks(client, data as Parameters<typeof withOptOutTasks>[1]);
		return json(queue, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not load the texting setup queue.', error);
		return json({ error: 'The to-do list could not be loaded.' }, { status: 500 });
	}
};
