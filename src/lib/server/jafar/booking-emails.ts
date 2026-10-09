import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import { bookingManageUrl } from '$lib/server/jafar/booking-links';
import {
	bookingPath,
	dateWords,
	lengthWords,
	timeWords,
	zoneCity,
	type BookingView
} from '$lib/jafar/booking';

// Jafar business management E1/E2: every email a visitor gets about their booking, queued through the durable
// outbox so a provider outage is retried rather than lost. Times are in the zone the visitor booked in. While the
// booking can still change, each email carries the visitor's link to change or cancel it.

export type BookingEmailKind =
	| { kind: 'booked' }
	| { kind: 'requested' }
	/** `requestedStartsAt`: the time they asked for, when Jafar approved a different one. */
	| { kind: 'approved'; requestedStartsAt?: string }
	| { kind: 'declined' }
	| { kind: 'moved'; fromStartsAt: string; by: 'visitor' | 'staff' }
	| { kind: 'cancelled'; by: 'visitor' | 'staff' }
	/** E3: the call is now with another host; `changeId` tells one change from the next. */
	| { kind: 'host_changed'; fromHostName: string; changeId: string };

function escapeHtml(value: string) {
	return value
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;');
}

type Line = string | { label: string; href: string };

/** The email's words, apart so a test can read them. */
export function bookingEmail(booking: BookingView, email: BookingEmailKind, origin: string) {
	const zone = booking.visitor_time_zone;
	const firstName = booking.visitor_name.split(/\s+/)[0] || booking.visitor_name;
	const date = dateWords(booking.starts_at, zone, 'en-GB');
	const start = timeWords(booking.starts_at, zone, 'en-GB');
	const when = `${date}, ${start} – ${timeWords(booking.ends_at, zone, 'en-GB')} (${zoneCity(zone)} time)`;
	const at = (instant: string) =>
		`${dateWords(instant, zone, 'en-GB')} at ${timeWords(instant, zone, 'en-GB')}`;
	const call = `${booking.name} (${lengthWords(booking.duration_minutes)}) with ${booking.host_name}`;
	const how = `${booking.host_name} will phone you on ${booking.visitor_phone}.`;
	const details: Line[] = [`When: ${when}`, `How: ${how}`];
	const manage = bookingManageUrl(origin, booking.booking_id);
	const bookAgain = booking.slug ? `${origin}${bookingPath(booking.slug)}` : null;
	const deadline =
		new Date(booking.change_until).getTime() < new Date(booking.starts_at).getTime()
			? ` until ${at(booking.change_until)}`
			: '';
	const changeLinks: Line[] = booking.can_change
		? [
				`Need a different time, or can't make it? You can change or cancel${deadline}:`,
				{ label: 'Change or cancel', href: manage }
			]
		: [];
	const bookAgainLines = (words: string): Line[] =>
		bookAgain ? [words, { label: 'Choose a time', href: bookAgain }] : [];

	let subject: string;
	let body: Line[][];
	switch (email.kind) {
		case 'booked':
			subject = `Booked: ${booking.name} with Uplift, ${date} at ${start}`;
			body = [[`Your ${call} is booked.`], details, changeLinks];
			break;
		case 'requested':
			subject = `Request received: ${booking.name} with Uplift, ${date} at ${start}`;
			body = [
				[`Thanks — we have your request for a ${call}.`],
				details,
				[`${booking.host_name} will confirm it by email. The time is not held for you until then.`],
				changeLinks
			];
			break;
		case 'approved':
			subject = `Confirmed: ${booking.name} with Uplift, ${date} at ${start}`;
			body = [
				[
					email.requestedStartsAt && email.requestedStartsAt !== booking.starts_at
						? `${at(email.requestedStartsAt)} was no longer free, so ${booking.host_name} booked your ${call} for the time below.`
						: `${booking.host_name} has confirmed your ${call}.`
				],
				details,
				changeLinks
			];
			break;
		case 'declined':
			subject = `Not booked: ${booking.name} with Uplift, ${date} at ${start}`;
			body = [
				[
					`Sorry — ${booking.host_name} can't take your request for ${at(booking.starts_at)} (${zoneCity(zone)} time).`
				],
				bookAgainLines('Please choose another time that suits you:')
			];
			break;
		case 'moved':
			subject = `Moved: ${booking.name} with Uplift, now ${date} at ${start}`;
			body = [
				[
					email.by === 'visitor'
						? `Your ${call} has moved from ${at(email.fromStartsAt)} to the time below.`
						: `We have had to move your ${call} from ${at(email.fromStartsAt)} to the time below. If it doesn't suit you, change it with the link below.`
				],
				details,
				changeLinks
			];
			break;
		case 'cancelled':
			subject = `Cancelled: ${booking.name} with Uplift, ${date} at ${start}`;
			body = [
				[
					email.by === 'visitor'
						? `Your ${call} on ${at(booking.starts_at)} is cancelled.`
						: `Sorry — we have had to cancel your ${call} on ${at(booking.starts_at)}.`
				],
				bookAgainLines(
					email.by === 'visitor' ? 'Want to talk another time?' : 'Please choose a new time:'
				)
			];
			break;
		case 'host_changed':
			subject = `New host: ${booking.name} with Uplift, ${date} at ${start}`;
			body = [
				[
					`Your ${booking.name} is now with ${booking.host_name} instead of ${email.fromHostName}. The time has not changed.`
				],
				details,
				changeLinks
			];
			break;
	}

	const paragraphs = [[`Hi ${firstName},`], ...body.filter((lines) => lines.length), ['Uplift']];
	const text = paragraphs
		.map((lines) =>
			lines
				.map((line) => (typeof line === 'string' ? line : `${line.label}: ${line.href}`))
				.join('\n')
		)
		.join('\n\n');
	const html = paragraphs
		.map(
			(lines) =>
				`<p>${lines
					.map((line) =>
						typeof line === 'string'
							? escapeHtml(line).replace(/^(When|How):/, '<strong>$1:</strong>')
							: `<a href="${escapeHtml(line.href)}">${escapeHtml(line.label)}</a>`
					)
					.join('<br>')}</p>`
		)
		.join('');
	return { subject, text, html };
}

/** One send per booking event; moving twice to different times sends twice, a retried request once. */
function idempotencyKey(booking: BookingView, email: BookingEmailKind) {
	const base = `booking:${booking.booking_id}:${email.kind}`;
	if (email.kind === 'moved') return `${base}:${booking.starts_at}`;
	if (email.kind === 'host_changed') return `${base}:${email.changeId}`;
	return base;
}

export async function sendBookingEmail(
	client: SupabaseClient<Database>,
	booking: BookingView,
	email: BookingEmailKind,
	origin: string
) {
	const content = bookingEmail(booking, email, origin);
	await enqueueEmailDelivery(client, {
		templateKey: `booking_${email.kind}`,
		target: { targetKind: 'platform', targetId: null },
		idempotencyKey: idempotencyKey(booking, email),
		recipientEmail: booking.visitor_email,
		subject: content.subject,
		htmlContent: content.html,
		textContent: content.text
	});
}
