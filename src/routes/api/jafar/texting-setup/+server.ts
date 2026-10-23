import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { withOptOutTasks } from '$lib/server/communications/sms-opt-out-tasks';
import {
	unpaidNumberTasks,
	withUnpaidNumberTasks
} from '$lib/server/communications/sms-unpaid-number-tasks';

// Stage 10 Part 5b: the Texting setup page. Every country a business asked for that still waits on Uplift,
// oldest first, the opt-out words they need (Part 5d), numbers that couldn't renew (Part 7), and the page's four numbers. Read-only; the task's buttons post to the routes below.
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	try {
		const client = getOwnerSupabaseClient();
		const { data, error } = await client.rpc('communication_sms_destination_queue');
		if (error) throw error;
		const [queue, unpaid] = await Promise.all([
			withOptOutTasks(client, data as Parameters<typeof withOptOutTasks>[1]),
			unpaidNumberTasks(client)
		]);
		return json(withUnpaidNumberTasks(queue, unpaid), {
			headers: { 'cache-control': 'no-store' }
		});
	} catch (error) {
		console.error('Could not load the texting setup queue.', error);
		return json({ error: 'The to-do list could not be loaded.' }, { status: 500 });
	}
};
