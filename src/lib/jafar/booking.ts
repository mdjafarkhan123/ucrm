// Jafar business management E1: sales booking -- the public page where a prospect books a call, and Jafar's
// Booking settings. The database decides which times are open (private.booking_open_slots); this module holds the
// shapes, the choices the settings offer, and the words both pages share.

export type LocationKind = 'phone';

export type MeetingType = {
	id: string;
	slug: string;
	name: string;
	description: string | null;
	duration_minutes: number;
	location_kind: LocationKind;
	min_notice_minutes: number;
	horizon_days: number;
	buffer_minutes: number;
	slot_interval_minutes: number;
	/** E2: each booking waits for Jafar's approval; a request holds no time. */
	requires_approval: boolean;
	/** E2: how long before the call the visitor's change and cancel links stop working. */
	change_deadline_minutes: number;
};

/** One weekly range; weekday 0 is Sunday. Times are "HH:MM" in the host's time zone. */
export type BookingHours = { weekday: number; start: string; end: string };

export type BookingSettings = {
	enabled: boolean;
	/** Jafar's saved time zone; null until he saves one (the browser's is then saved with the settings). */
	time_zone: string | null;
	meeting_type: MeetingType;
	hours: BookingHours[];
	bookings_count: number;
};

/** What the public page shows about a link. */
export type PublicMeetingType = {
	slug: string;
	name: string;
	description: string | null;
	duration_minutes: number;
	location_kind: LocationKind;
	horizon_days: number;
	host_name: string;
};

export type BookingSlot = { starts_at: string; ends_at: string };

export type BookedCall = {
	starts_at: string;
	ends_at: string;
	name: string;
	duration_minutes: number;
	location_kind: LocationKind;
	host_name: string;
};

/**
 * E2: a booking or request as its visitor's link and its emails see it. `status`: a request (no time held yet),
 * a booking (its call's own `call_status` says scheduled, held, missed or cancelled), declined, or withdrawn.
 */
export type BookingView = BookedCall & {
	booking_id: string;
	status: 'requested' | 'booked' | 'declined' | 'withdrawn';
	call_status: 'scheduled' | 'held' | 'no_show' | 'cancelled' | null;
	entry_id: string | null;
	relationship_id: string;
	slug: string | null;
	horizon_days: number;
	visitor_name: string;
	visitor_email: string;
	visitor_phone: string;
	visitor_time_zone: string;
	business_name: string;
	/** The visitor's links stop working at this time (Jafar's deadline before the call). */
	change_until: string;
	can_change: boolean;
};

/** What the visitor's link page shows: the booking and where to book again. */
export type ManagedBooking = Omit<BookingView, 'visitor_email' | 'relationship_id' | 'entry_id'>;

// --- Choices -------------------------------------------------------------------------------------------------

export const DURATION_CHOICES = [15, 20, 30, 45, 60, 90] as const;
export const INTERVAL_CHOICES = [10, 15, 20, 30, 45, 60, 90, 120] as const;
export const BUFFER_CHOICES = [0, 5, 10, 15, 30, 45, 60] as const;
/** Minimum notice, in minutes. */
export const NOTICE_CHOICES = [0, 60, 120, 240, 720, 1440, 2880, 4320, 10080] as const;
/** E2: how long before the call a visitor can still change or cancel, in minutes. */
export const CHANGE_DEADLINE_CHOICES = [0, 60, 120, 240, 720, 1440, 2880] as const;
export const HORIZON_CHOICES = [7, 14, 30, 60, 90, 180] as const;
export const MAX_RANGES_PER_DAY = 4;

/** Monday first, as a work week reads; values are the database's weekday (0 is Sunday). */
export const WEEKDAYS = [
	{ value: 1, name: 'Monday', short: 'Mon' },
	{ value: 2, name: 'Tuesday', short: 'Tue' },
	{ value: 3, name: 'Wednesday', short: 'Wed' },
	{ value: 4, name: 'Thursday', short: 'Thu' },
	{ value: 5, name: 'Friday', short: 'Fri' },
	{ value: 6, name: 'Saturday', short: 'Sat' },
	{ value: 0, name: 'Sunday', short: 'Sun' }
] as const;

export const LOCATION_WORDS: Record<LocationKind, string> = { phone: 'Phone call' };

/** The public link's path for a meeting type. */
export function bookingPath(slug: string) {
	return `/book/${slug}`;
}

/** "Discovery Call!" -> "discovery-call" */
export function slugify(value: string) {
	return value
		.toLowerCase()
		.normalize('NFKD')
		.replace(/[̀-ͯ]/g, '')
		.replace(/[^a-z0-9]+/g, '-')
		.replace(/^-+|-+$/g, '')
		.slice(0, 60)
		.replace(/-+$/g, '');
}

/** "30 min", "1 hr", "1 hr 30 min". */
export function lengthWords(minutes: number) {
	const hours = Math.floor(minutes / 60);
	const rest = minutes % 60;
	if (hours === 0) return `${rest} min`;
	return rest === 0 ? `${hours} hr` : `${hours} hr ${rest} min`;
}

/** "No notice", "4 hours", "1 day", "1 week". */
export function noticeWords(minutes: number) {
	if (minutes === 0) return 'No notice';
	if (minutes % 10080 === 0) return plural(minutes / 10080, 'week');
	if (minutes % 1440 === 0) return plural(minutes / 1440, 'day');
	if (minutes % 60 === 0) return plural(minutes / 60, 'hour');
	return plural(minutes, 'minute');
}

function plural(value: number, unit: string) {
	return `${value} ${unit}${value === 1 ? '' : 's'}`;
}

// --- Times in the visitor's zone -------------------------------------------------------------------------------

/** The calendar day ("2026-10-14") an instant falls on in a zone. */
export function dayKey(instant: string | Date, zone: string) {
	const parts = new Intl.DateTimeFormat('en-CA', {
		timeZone: zone,
		year: 'numeric',
		month: '2-digit',
		day: '2-digit'
	}).formatToParts(typeof instant === 'string' ? new Date(instant) : instant);
	const get = (type: string) => parts.find((part) => part.type === type)?.value ?? '';
	return `${get('year')}-${get('month')}-${get('day')}`;
}

/** Open times grouped by the day they fall on in the visitor's zone, each day's times in order. */
export function slotsByDay(slots: BookingSlot[], zone: string) {
	const days = new Map<string, BookingSlot[]>();
	for (const slot of slots) {
		const key = dayKey(slot.starts_at, zone);
		const list = days.get(key);
		if (list) list.push(slot);
		else days.set(key, [slot]);
	}
	return days;
}

/** "3:00 pm" in the zone and the reader's language. */
export function timeWords(instant: string, zone: string, locale?: string) {
	return new Intl.DateTimeFormat(locale, {
		timeZone: zone,
		hour: 'numeric',
		minute: '2-digit'
	}).format(new Date(instant));
}

/** "Tuesday, 14 October 2026" in the zone and the reader's language. */
export function dateWords(instant: string, zone: string, locale?: string) {
	return new Intl.DateTimeFormat(locale, {
		timeZone: zone,
		weekday: 'long',
		day: 'numeric',
		month: 'long',
		year: 'numeric'
	}).format(new Date(instant));
}

/** "Europe/London" -> "London"; "America/Argentina/Buenos_Aires" -> "Buenos Aires". */
export function zoneCity(zone: string) {
	return (zone.split('/').pop() ?? zone).replace(/_/g, ' ');
}

// --- Jafar's settings (browser) --------------------------------------------------------------------------------

export async function fetchBookingSettings(): Promise<BookingSettings> {
	const response = await fetch('/api/jafar/booking');
	const result = await response.json();
	if (!response.ok) throw new Error(result.error ?? 'Booking settings could not be loaded.');
	return result;
}

/** What the settings page sends; `time_zone` is the browser's, saved as Jafar's when he has none yet. */
export type BookingSettingsInput = {
	enabled: boolean;
	meeting_type: Omit<MeetingType, 'location_kind'>;
	hours: BookingHours[];
	time_zone?: string;
};
