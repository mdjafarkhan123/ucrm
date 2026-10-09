import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import { dateWords, lengthWords, timeWords, zoneCity, type BookedCall } from '$lib/jafar/booking';

// Jafar business management E1: the visitor's confirmation, queued through the durable outbox so a provider outage
// is retried rather than lost. Times are in the zone the visitor booked in. Self-service reschedule and cancel
// links arrive in E2; until then the email says to reply.

function escapeHtml(value: string) {
	return value
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;');
}

export type BookingConfirmation = {
	bookingId: string;
	call: BookedCall;
	visitorName: string;
	visitorEmail: string;
	visitorPhone: string;
	timeZone: string;
};

/** The email's words, apart so a test can read them. */
export function bookingConfirmationEmail(params: BookingConfirmation) {
	const { call, timeZone } = params;
	const firstName = params.visitorName.split(/\s+/)[0] || params.visitorName;
	const date = dateWords(call.starts_at, timeZone, 'en-GB');
	const start = timeWords(call.starts_at, timeZone, 'en-GB');
	const end = timeWords(call.ends_at, timeZone, 'en-GB');
	const when = `${date}, ${start} – ${end} (${zoneCity(timeZone)} time)`;
	const how = `${call.host_name} will phone you on ${params.visitorPhone}.`;

	const subject = `Booked: ${call.name} with Uplift, ${date} at ${start}`;
	const text = [
		`Hi ${firstName},`,
		'',
		`Your ${call.name} (${lengthWords(call.duration_minutes)}) with ${call.host_name} is booked.`,
		'',
		`When: ${when}`,
		`How: ${how}`,
		'',
		'Need a different time? Just reply to this email and we will sort it out.',
		'',
		'Uplift'
	].join('\n');
	const html = [
		`<p>Hi ${escapeHtml(firstName)},</p>`,
		`<p>Your ${escapeHtml(call.name)} (${lengthWords(call.duration_minutes)}) with ${escapeHtml(call.host_name)} is booked.</p>`,
		`<p><strong>When:</strong> ${escapeHtml(when)}<br><strong>How:</strong> ${escapeHtml(how)}</p>`,
		'<p>Need a different time? Just reply to this email and we will sort it out.</p>',
		'<p>Uplift</p>'
	].join('');
	return { subject, text, html };
}

export async function sendBookingConfirmation(
	client: SupabaseClient<Database>,
	params: BookingConfirmation
) {
	const email = bookingConfirmationEmail(params);
	await enqueueEmailDelivery(client, {
		templateKey: 'booking_confirmation',
		target: { targetKind: 'platform', targetId: null },
		idempotencyKey: `booking:${params.bookingId}:confirmation`,
		recipientEmail: params.visitorEmail,
		subject: email.subject,
		htmlContent: email.html,
		textContent: email.text
	});
}
