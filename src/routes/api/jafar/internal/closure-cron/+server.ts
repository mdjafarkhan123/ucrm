import { timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { runOrganizationClosureCron } from '$lib/server/jafar/organization-closure-cron';

function isAuthorized(request: Request): boolean {
	const header = request.headers.get('authorization') ?? '';
	const [scheme, token] = header.split(' ');
	if (scheme !== 'Bearer' || !token) return false;

	const expected = Buffer.from(getServerEnv().CLOSURE_CRON_SECRET);
	const provided = Buffer.from(token);
	return provided.length === expected.length && timingSafeEqual(provided, expected);
}

/**
 * Triggered once daily by a pg_cron job (via net.http_post), never by a browser -- there is no
 * owner session to check here, only this shared secret. Runs the closure-notice and purge sweep
 * and returns a plain summary; failures within the sweep are already durably tracked through
 * platform_operation_attempts and owner alerts by the sweep itself, so this handler's only job is
 * authorization and reporting the outcome counts.
 */
export const POST: RequestHandler = async ({ request }) => {
	if (!isAuthorized(request)) {
		return json({ error: 'Unauthorized.' }, { status: 401 });
	}

	const client = getOwnerSupabaseClient();

	try {
		const result = await runOrganizationClosureCron(client);
		return json(result);
	} catch (error) {
		console.error('The organization closure cron sweep failed.', error);
		return json({ error: 'The closure cron sweep failed.' }, { status: 500 });
	}
};
