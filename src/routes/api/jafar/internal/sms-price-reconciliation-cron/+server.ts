import { timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { createSupabaseSmsPriceReconciliationStore } from '$lib/server/communications/sms-price-reconciliation-store';
import { runSmsPriceReconciliationCron } from '$lib/server/communications/sms-price-reconciliation-cron';

function isAuthorized(request: Request): boolean {
	const expected = getServerEnv().SMS_PRICE_RECONCILIATION_CRON_SECRET;
	if (!expected) return false;
	const header = request.headers.get('authorization') ?? '';
	const [scheme, token] = header.split(' ');
	if (scheme !== 'Bearer' || !token) return false;

	const expectedBuffer = Buffer.from(expected);
	const provided = Buffer.from(token);
	return provided.length === expectedBuffer.length && timingSafeEqual(provided, expectedBuffer);
}

/**
 * Stage 8 part 1's poll trigger, called by a pg_cron job (via net.http_post) every 30 minutes -- there is no
 * owner session here, only this shared secret. Mirrors trust-hub-status-cron/+server.ts exactly.
 */
export const POST: RequestHandler = async ({ request }) => {
	if (!isAuthorized(request)) {
		return json({ error: 'Unauthorized.' }, { status: 401 });
	}

	const client = getOwnerSupabaseClient();
	const store = createSupabaseSmsPriceReconciliationStore(client);

	try {
		const result = await runSmsPriceReconciliationCron(store);
		return json(result);
	} catch (error) {
		console.error('The SMS price-reconciliation cron failed.', error);
		return json({ error: 'The SMS price-reconciliation cron failed.' }, { status: 500 });
	}
};
