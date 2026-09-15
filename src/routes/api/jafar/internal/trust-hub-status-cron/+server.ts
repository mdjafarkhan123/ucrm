import { timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { createSupabaseTrustHubSubmissionStore } from '$lib/server/communications/trust-hub-submission-store';
import { createTwilioTrustHubClient } from '$lib/server/communications/twilio-trust-hub';
import { createSupabaseTrustHubStatusTriggerStore } from '$lib/server/communications/trust-hub-status-trigger-store';
import { runTrustHubStatusPollCron } from '$lib/server/communications/trust-hub-status-poll-cron';

function isAuthorized(request: Request): boolean {
	const expected = getServerEnv().TRUST_HUB_STATUS_CRON_SECRET;
	if (!expected) return false;
	const header = request.headers.get('authorization') ?? '';
	const [scheme, token] = header.split(' ');
	if (scheme !== 'Bearer' || !token) return false;

	const expectedBuffer = Buffer.from(expected);
	const provided = Buffer.from(token);
	return provided.length === expectedBuffer.length && timingSafeEqual(provided, expectedBuffer);
}

/**
 * Stage 9D's daily safety net, triggered by a pg_cron job (via net.http_post), never by a browser -- there is
 * no owner session to check here, only this shared secret. Mirrors closure-cron/+server.ts exactly. Backs up
 * the Trust Hub Event Streams webhook (trust-hub-events/+server.ts), which is the primary, near-real-time
 * path; this route only re-checks what the webhook hasn't yet resolved.
 */
export const POST: RequestHandler = async ({ request }) => {
	if (!isAuthorized(request)) {
		return json({ error: 'Unauthorized.' }, { status: 401 });
	}

	const client = getOwnerSupabaseClient();
	const deps = {
		store: createSupabaseTrustHubSubmissionStore(client),
		twilio: createTwilioTrustHubClient()
	};
	const triggerStore = createSupabaseTrustHubStatusTriggerStore(client);

	try {
		const result = await runTrustHubStatusPollCron(deps, triggerStore);
		return json(result);
	} catch (error) {
		console.error('The Trust Hub status poll cron failed.', error);
		return json({ error: 'The Trust Hub status poll cron failed.' }, { status: 500 });
	}
};
