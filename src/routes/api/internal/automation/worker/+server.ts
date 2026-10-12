import { randomUUID, timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { runMonitoredAutomationWake } from '$lib/server/automation/worker';
import { drainTeamAlertEmails } from '$lib/server/team/inquiry-alerts';
import { drainBrowserAlerts } from '$lib/server/team/browser-alerts';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

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
//
// Part 12: the same wake also raises long-running-timer alerts and sends browser alerts.
// Part 4 Stage 4: the same one-minute wake also sends team alert emails about website inquiries, alongside the
// automation drain rather than after it, so a slow automation batch never delays a speed-to-lead alert. Its own
// time budget keeps it under the same deadline, and a failure there never fails the automation wake.
export const POST: RequestHandler = async ({ request }) => {
	if (!authorized(request))
		return json(
			{ error: 'Unauthorized.' },
			{ status: 401, headers: { 'cache-control': 'no-store' } }
		);

	const wakeCorrelationId = request.headers.get('x-wake-correlation-id') ?? randomUUID();
	const [result, teamAlerts, browserAlerts] = await Promise.all([
		runMonitoredAutomationWake({ wakeCorrelationId }),
		drainTeamAlertEmails().catch((error: unknown) => {
			console.error('Could not send team alert emails.', error);
			return { error: 'team_alert_emails_failed' as const };
		}),
		// Part 12: first raise the "timer running over 12 hours" alerts that are now due, then send browser
		// alerts. Like the emails, a fault here never fails the automation wake.
		(async () => {
			const raised = await getOwnerSupabaseClient().rpc('create_long_timer_alerts');
			if (raised.error) throw new Error(raised.error.message);
			return drainBrowserAlerts();
		})().catch((error: unknown) => {
			console.error('Could not send browser alerts.', error);
			return { error: 'browser_alerts_failed' as const };
		})
	]);
	return json(
		{ ...result, team_alert_emails: teamAlerts, browser_alerts: browserAlerts },
		{ headers: { 'cache-control': 'no-store' } }
	);
};
