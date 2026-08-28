import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Jafar's recovery queue: every message that stopped moving on its own, newest trouble first, across
// all tenants (docs/contractor-email-contract.md § Queueing, retries, and history).
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const { data, error } = await getOwnerSupabaseClient().rpc(
		'get_communication_message_recovery_queue'
	);
	if (error) {
		console.error('Could not load the message recovery queue.', error);
		return json(
			{ error: 'The recovery queue could not be loaded.' },
			{ status: 500, headers: { 'cache-control': 'no-store' } }
		);
	}

	return json(data, { headers: { 'cache-control': 'no-store' } });
};
