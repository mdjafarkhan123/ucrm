import { timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { createSupabaseSmsUsageReconciliationStore } from '$lib/server/communications/sms-usage-reconciliation-store';
import { runSmsUsageReconciliationCron } from '$lib/server/communications/sms-usage-reconciliation-cron';

function isAuthorized(request: Request): boolean {
	const expected = getServerEnv().SMS_USAGE_RECONCILIATION_CRON_SECRET;
	if (!expected) return false;
	const header = request.headers.get('authorization') ?? '';
	const [scheme, token] = header.split(' ');
	if (scheme !== 'Bearer' || !token) return false;

	const expectedBuffer = Buffer.from(expected);
	const provided = Buffer.from(token);
	return provided.length === expectedBuffer.length && timingSafeEqual(provided, expectedBuffer);
}

/**
 * Stage 8 part 2's daily poll trigger, called by a pg_cron job (via net.http_post) -- there is no owner
 * session here, only this shared secret. Mirrors sms-price-reconciliation-cron/+server.ts exactly.
 */
export const POST: RequestHandler = async ({ request }) => {
	if (!isAuthorized(request)) {
		return json({ error: 'Unauthorized.' }, { status: 401 });
	}

	const client = getOwnerSupabaseClient();
	const store = createSupabaseSmsUsageReconciliationStore(client);

	try {
		const result = await runSmsUsageReconciliationCron(store);
		return json(result);
	} catch (error) {
		console.error('The SMS usage-reconciliation cron failed.', error);
		return json({ error: 'The SMS usage-reconciliation cron failed.' }, { status: 500 });
	}
};
