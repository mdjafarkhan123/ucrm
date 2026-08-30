import { randomUUID, timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { runMonitoredEmailWake } from '$lib/server/communications/email-worker';

function authorized(request: Request) {
	const token = request.headers.get('authorization')?.match(/^Bearer (.+)$/i)?.[1];
	const expected = getServerEnv().COMMUNICATIONS_WORKER_SECRET;
	if (!token || !expected) return false;
	const provided = Buffer.from(token);
	const wanted = Buffer.from(expected);
	return provided.length === wanted.length && timingSafeEqual(provided, wanted);
}

// This handler runs one monitored email drain. The Cron dispatch carries a wake correlation id so the run is
// attributable in the ledger; a direct (manual) invocation without one gets a fresh id. A single-flight lease
// keeps two wakes from draining at once (already_running is a 2xx no-op), and a whole-route deadline bounds
// wall time under the pg_net HTTP timeout. pg_net treats a returned request id as success, so health monitors
// the HTTP status this returns rather than assuming the drain finished.
export const POST: RequestHandler = async ({ request }) => {
	if (!authorized(request))
		return json(
			{ error: 'Unauthorized.' },
			{ status: 401, headers: { 'cache-control': 'no-store' } }
		);

	const wakeCorrelationId = request.headers.get('x-wake-correlation-id') ?? randomUUID();
	const result = await runMonitoredEmailWake({ wakeCorrelationId });
	return json(result, { headers: { 'cache-control': 'no-store' } });
};
