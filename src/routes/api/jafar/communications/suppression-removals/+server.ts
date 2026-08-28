import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Jafar's review queue: complaint-suppression removal requests waiting on his decision, plus a short
// tail of the ones he has recently decided (docs/contractor-email-contract.md § Platform Owner
// controls -- "sender restrictions, suppressions, unusual volume, and provider incidents").
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const { data, error } = await getOwnerSupabaseClient().rpc(
		'get_communication_email_suppression_removal_queue'
	);
	if (error) {
		console.error('Could not load the suppression removal queue.', error);
		return json(
			{ error: 'The removal queue could not be loaded.' },
			{ status: 500, headers: { 'cache-control': 'no-store' } }
		);
	}

	return json(data, { headers: { 'cache-control': 'no-store' } });
};
