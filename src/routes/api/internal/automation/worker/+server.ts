import { randomUUID, timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { runMonitoredAutomationWake } from '$lib/server/automation/worker';

function authorized(request: Request) {
	const token = request.headers.get('authorization')?.match(/^Bearer (.+)$/i)?.[1];
	const expected = getServerEnv().AUTOMATION_WORKER_SECRET;
	if (!token || !expected) return false;
	const provided = Buffer.from(token);
	const wanted = Buffer.from(expected);
	return provided.length === wanted.length && timingSafeEqual(provided, wanted);
}

// One monitored automation wake: intake, then bounded fair claims of due work. The Cron dispatch carries a
// wake correlation id so the run is attributable in the ledger; a direct invocation gets a fresh one.
//
// Unlike the email worker there is NO single-flight lease, so overlapping wakes are allowed to run together —
// per-row claims are the exactly-once boundary. A whole-route deadline bounds wall time under the pg_net HTTP
// timeout. pg_net treats a returned request id as success, so health monitors the HTTP status this returns.
export const POST: RequestHandler = async ({ request }) => {
	if (!authorized(request))
		return json(
			{ error: 'Unauthorized.' },
			{ status: 401, headers: { 'cache-control': 'no-store' } }
		);

	const wakeCorrelationId = request.headers.get('x-wake-correlation-id') ?? randomUUID();
	const result = await runMonitoredAutomationWake({ wakeCorrelationId });
	return json(result, { headers: { 'cache-control': 'no-store' } });
};
