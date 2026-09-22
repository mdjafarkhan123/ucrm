import { randomUUID, timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { runMonitoredMarketingWake } from '$lib/server/marketing/dispatcher';

function authorized(request: Request) {
	const token = request.headers.get('authorization')?.match(/^Bearer (.+)$/i)?.[1];
	const expected = getServerEnv().COMMUNICATIONS_WORKER_SECRET;
	if (!token || !expected) return false;
	const provided = Buffer.from(token);
	const wanted = Buffer.from(expected);
	return provided.length === wanted.length && timingSafeEqual(provided, wanted);
}

// This handler runs one monitored marketing-campaign drain, the same auth and lease/deadline shape as
// email-worker/+server.ts (shared COMMUNICATIONS_WORKER_SECRET bearer, single-flight lease, hard route
// deadline). pg_net treats a returned request id as success, so health monitors the HTTP status this
// returns rather than assuming the drain finished.
export const POST: RequestHandler = async ({ request }) => {
	if (!authorized(request))
		return json(
			{ error: 'Unauthorized.' },
			{ status: 401, headers: { 'cache-control': 'no-store' } }
		);

	const wakeCorrelationId = request.headers.get('x-wake-correlation-id') ?? randomUUID();
	const result = await runMonitoredMarketingWake({ wakeCorrelationId });
	return json(result, { headers: { 'cache-control': 'no-store' } });
};
