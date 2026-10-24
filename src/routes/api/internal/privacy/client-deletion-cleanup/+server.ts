import { timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { runClientDeletionCleanupSweep } from '$lib/server/privacy/client-deletion-cleanup';

function isAuthorized(request: Request): boolean {
	const expected = getServerEnv().CLIENT_DELETION_CRON_SECRET;
	if (!expected) return false;
	const header = request.headers.get('authorization') ?? '';
	const [scheme, token] = header.split(' ');
	if (scheme !== 'Bearer' || !token) return false;

	const expectedBuffer = Buffer.from(expected);
	const provided = Buffer.from(token);
	return provided.length === expectedBuffer.length && timingSafeEqual(provided, expectedBuffer);
}

/**
 * Data privacy Part 3b's daily retry, called by the client-deletion-cleanup-daily pg_cron job (via
 * net.http_post) -- there is no session here, only this shared secret. Finishes the stored-file cleanup of any
 * permanent customer delete that could not finish straight away; failures are already recorded on the receipt
 * and raised to Jafar by the sweep, so this only authorizes and reports the counts.
 */
export const POST: RequestHandler = async ({ request }) => {
	if (!isAuthorized(request)) {
		return json({ error: 'Unauthorized.' }, { status: 401 });
	}

	try {
		const result = await runClientDeletionCleanupSweep(getOwnerSupabaseClient());
		return json(result);
	} catch (error) {
		console.error('The client-deletion cleanup sweep failed.', error);
		return json({ error: 'The client-deletion cleanup sweep failed.' }, { status: 500 });
	}
};
