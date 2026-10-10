import { VIDEO_PROVIDER_WORDS, type BookingView } from '$lib/jafar/booking';

// Jafar business management E2b: a visitor adds their booked call to their own calendar from the links in its emails
// (Calendly's and Cal.com's "Add to calendar"): Google Calendar through its event template link, and Apple, Outlook
// and the rest through an .ics file served from the visitor's booking link. The file's UID is the booking's, so a
// calendar that imports a newer file after a move updates the event rather than adding a second one.

const PRODUCT = '-//Uplift//Sales booking//EN';

/** "20261014T090000Z" */
function utcStamp(iso: string) {
	return new Date(iso)
		.toISOString()
		.replace(/[-:]/g, '')
		.replace(/\.\d{3}/, '');
}

/** RFC 5545 text: backslash, semicolon, comma and line breaks escaped. */
function text(value: string) {
	return value
		.replace(/\\/g, '\\\\')
		.replace(/;/g, '\\;')
		.replace(/,/g, '\\,')
		.replace(/\r?\n/g, '\\n');
}

/** RFC 5545 folds lines longer than 75 octets, each continuation starting with a space. */
function fold(line: string) {
	const bytes = new TextEncoder().encode(line);
	if (bytes.length <= 75) return line;
	const parts: string[] = [];
	let current = '';
	let size = 0;
	for (const character of line) {
		const length = new TextEncoder().encode(character).length;
		const limit = parts.length === 0 ? 75 : 74;
		if (size + length > limit) {
			parts.push(current);
			current = '';
			size = 0;
		}
		current += character;
		size += length;
	}
	parts.push(current);
	return parts.join('\r\n ');
}

function summary(booking: BookingView) {
	return `${booking.name} with Uplift`;
}

/** E4a: where the call happens -- the joining link, the details still to follow, or the visitor's phone. */
function location(booking: BookingView) {
	if (booking.location_kind === 'phone') return `Phone: ${booking.visitor_phone}`;
	return (
		booking.video_join_url ??
		`${VIDEO_PROVIDER_WORDS[booking.location_kind]} (link to follow by email)`
	);
}

function how(booking: BookingView) {
	if (booking.location_kind === 'phone')
		return `${booking.host_name} will phone you on ${booking.visitor_phone}.`;
	const provider = VIDEO_PROVIDER_WORDS[booking.location_kind];
	return booking.video_join_url
		? `Join the ${provider} call: ${booking.video_join_url}`
		: `${provider} video call. We will email you the joining link before the call.`;
}

function description(booking: BookingView, manageUrl: string) {
	return [how(booking), booking.can_change ? `Change or cancel: ${manageUrl}` : null]
		.filter(Boolean)
		.join('\n');
}

/** The booking as a one-event calendar file; a cancelled call is sent as cancelled so a re-import removes it. */
export function bookingIcs(booking: BookingView, manageUrl: string, now = new Date()) {
	const cancelled = booking.status !== 'booked' || booking.call_status === 'cancelled';
	const lines = [
		'BEGIN:VCALENDAR',
		'VERSION:2.0',
		`PRODID:${PRODUCT}`,
		'CALSCALE:GREGORIAN',
		'METHOD:PUBLISH',
		'BEGIN:VEVENT',
		`UID:booking-${booking.booking_id}@uplift`,
		// Seconds since 2026 keep rising with each download, so a newer file wins over an older one.
		`SEQUENCE:${Math.max(0, Math.floor((now.getTime() - Date.UTC(2026, 0, 1)) / 1000))}`,
		`DTSTAMP:${utcStamp(now.toISOString())}`,
		`DTSTART:${utcStamp(booking.starts_at)}`,
		`DTEND:${utcStamp(booking.ends_at)}`,
		`SUMMARY:${text(summary(booking))}`,
		`DESCRIPTION:${text(description(booking, manageUrl))}`,
		`LOCATION:${text(location(booking))}`,
		`STATUS:${cancelled ? 'CANCELLED' : 'CONFIRMED'}`,
		'TRANSP:OPAQUE',
		'END:VEVENT',
		'END:VCALENDAR'
	];
	return lines.map(fold).join('\r\n') + '\r\n';
}

/** Google Calendar's "add event" link with the call already filled in. */
export function googleCalendarUrl(booking: BookingView, manageUrl: string) {
	const params = new URLSearchParams({
		action: 'TEMPLATE',
		text: summary(booking),
		dates: `${utcStamp(booking.starts_at)}/${utcStamp(booking.ends_at)}`,
		details: description(booking, manageUrl),
		location: location(booking)
	});
	return `https://calendar.google.com/calendar/render?${params}`;
}

/** Where the visitor's .ics file is served: under their own booking link. */
export function bookingIcsUrl(manageUrl: string) {
	return `${manageUrl}/calendar.ics`;
}
