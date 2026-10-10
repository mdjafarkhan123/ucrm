import { randomUUID, timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { env } from '$env/dynamic/private';
import { runMonitoredEmailWake } from '$lib/server/communications/email-worker';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { emailDatabaseRaisedOwnerAlerts } from '$lib/server/jafar/owner-alerts';
import { sendDuePlatformReminders } from '$lib/server/jafar/reminders';
import { sweepVideoMeetings } from '$lib/server/jafar/video-sync';
import { sendDueSetupReminderEmails } from '$lib/server/setup/reminder-emails';
import { sendDueSupportUnseenReplyEmails } from '$lib/server/support/unseen-reply-emails';

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

	// Urgent alerts a database trigger raised (a contractor's protected email reserve running out) cannot
	// email Jafar from inside the database; this wake does it. Best effort: it never fails the drain's result.
	try {
		await emailDatabaseRaisedOwnerAlerts(getOwnerSupabaseClient(), {
			origin: env.APP_URL?.trim() || undefined
		});
	} catch (error) {
		console.error('Could not email database-raised owner alerts.', error);
	}

	// Support replies unseen for 3 minutes (onboarding D5b). Only a wake that held the lease sends them, so two
	// overlapping wakes never work the same reminders. Best effort: it never fails the drain's result.
	const origin = env.APP_URL?.trim();
	if (result.outcome !== 'already_running' && origin) {
		try {
			await sendDueSupportUnseenReplyEmails(getOwnerSupabaseClient(), { origin });
		} catch (error) {
			console.error('Could not email unseen support replies.', error);
		}

		// Setup untouched for about 24 hours, 3 days or 7 days (onboarding C6). Same lease, same best effort.
		try {
			await sendDueSetupReminderEmails(getOwnerSupabaseClient(), { origin });
		} catch (error) {
			console.error('Could not send setup reminder emails.', error);
		}

		// Business Management calls and follow-ups (Jafar business management C2): their alerts and emails. Same
		// lease, same best effort.
		try {
			await sendDuePlatformReminders(getOwnerSupabaseClient(), { origin });
		} catch (error) {
			console.error('Could not send calendar reminders.', error);
		}

		// Booked Zoom and Google Meet calls (E4b, E5): make, move or delete the meetings a booking is owed, retrying earlier failures.
		try {
			await sweepVideoMeetings(getOwnerSupabaseClient(), origin);
		} catch (error) {
			console.error('Could not sync video meetings.', error);
		}
	}

	return json(result, { headers: { 'cache-control': 'no-store' } });
};
