import { timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { drainMessengerWebhookEvents } from '$lib/server/communications/messenger-inbound-worker';
import { drainMessengerSendQueue } from '$lib/server/communications/messenger-send-worker';
import { checkDueMessengerConnections } from '$lib/server/communications/messenger-health-worker';

function authorized(request: Request) {
	const token = request.headers.get('authorization')?.match(/^Bearer (.+)$/i)?.[1];
	const expected = getServerEnv().COMMUNICATIONS_WORKER_SECRET;
	if (!token || !expected) return false;
	const provided = Buffer.from(token);
	const wanted = Buffer.from(expected);
	return provided.length === wanted.length && timingSafeEqual(provided, wanted);
}

// The one-minute cron's entry point (dispatch_communication_messenger_worker_wake): processes any Messenger
// deliveries the webhook's own instant wake did not finish, then sends any replies still waiting.
export const POST: RequestHandler = async ({ request }) => {
	if (!authorized(request))
		return json(
			{ error: 'Unauthorized.' },
			{ status: 401, headers: { 'cache-control': 'no-store' } }
		);

	const [messages, health] = await Promise.all([
		(async () => {
			const inbound = await drainMessengerWebhookEvents();
			const outbound = await drainMessengerSendQueue();
			return { ...inbound, outbound };
		})(),
		checkDueMessengerConnections()
	]);
	return json({ ...messages, health }, { headers: { 'cache-control': 'no-store' } });
};
