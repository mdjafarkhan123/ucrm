import { timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { runClientDeletionCleanupSweep } from '$lib/server/privacy/client-deletion-cleanup';
import { runScheduledClientDeletions } from '$lib/server/privacy/client-deletion-scheduled';

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
 * Called every hour by the client-deletion-hourly pg_cron job (via net.http_post) -- there is no session here,
 * only this shared secret. First deletes for good every customer whose 30 days in Recently Deleted are up (Data
 * privacy Part 6c), then finishes the stored-file cleanup of any permanent delete that could not finish straight
 * away (Part 3b). Failures are recorded and raised to Jafar by each step, so this only authorizes and reports.
 */
export const POST: RequestHandler = async ({ request }) => {
	if (!isAuthorized(request)) {
		return json({ error: 'Unauthorized.' }, { status: 401 });
	}

	try {
		const client = getOwnerSupabaseClient();
		const scheduled = await runScheduledClientDeletions(client);
		const cleanup = await runClientDeletionCleanupSweep(client);
		return json({ scheduled, ...cleanup });
	} catch (error) {
		console.error('The client-deletion cleanup sweep failed.', error);
		return json({ error: 'The client-deletion cleanup sweep failed.' }, { status: 500 });
	}
};
