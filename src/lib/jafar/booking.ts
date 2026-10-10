// Jafar business management E1/E3: sales booking -- the public page where a prospect books a call, and Jafar's
// Booking settings. The database decides which times are open (private.booking_open_slots); this module holds the
// shapes, the choices the settings offer, and the words both pages share.

export type LocationKind = 'phone' | 'zoom';

/** E4a: a video type's link -- UCRM makes the meeting (once its provider is connected), or the host adds one. */
export type VideoLinkMode = 'automatic' | 'custom';

export type MeetingType = {
	id: string;
	slug: string;
	name: string;
	description: string | null;
	duration_minutes: number;
	location_kind: LocationKind;
	video_link_mode: VideoLinkMode;
	min_notice_minutes: number;
	horizon_days: number;
	buffer_minutes: number;
	slot_interval_minutes: number;
	/** E2: each booking waits for Jafar's approval; a request holds no time. */
	requires_approval: boolean;
	/** E2: how long before the call the visitor's change and cancel links stop working. */
	change_deadline_minutes: number;
	/** E3: an Off type's link says booking is closed; its past bookings keep working. */
	is_active: boolean;
	/** E2b: when each reminder email goes to the visitor, in minutes before the call; empty sends none. */
	visitor_reminder_minutes: number[];
	/** E3: who takes every new booking (null is Jafar); always one of `host_member_ids`. */
	host_member_id: string | null;
	/** E3: who may host it (null is Jafar). */
	host_member_ids: (string | null)[];
	bookings_count: number;
};

/** One weekly range; weekday 0 is Sunday. Times are "HH:MM" in the host's time zone. */
export type BookingHours = { weekday: number; start: string; end: string };

/** E3: a person on the booking settings -- Jafar (null id) or a teammate who hosts or has hours -- with their zone. */
export type BookingPerson = { id: string | null; name: string; time_zone: string };

export type BookingSettings = {
	enabled: boolean;
	/** Jafar's saved time zone; null until he saves one (the browser's is then saved with the settings). */
	time_zone: string | null;
	meeting_types: MeetingType[];
	/** Every host's weekly ranges; `member_id` null is Jafar. */
	hours: (BookingHours & { member_id: string | null })[];
	people: BookingPerson[];
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
	/** E4a: a video call's joining link; null while it is still to follow. */
	video_join_url: string | null;
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
	/** E4a: a video call's joining link; null while its details are still to follow. */
	video_join_url: string | null;
	/** E4a: who made the link -- the provider's meeting, or one the host added. */
	video_link_source: 'provider' | 'custom' | null;
	video_link_mode: VideoLinkMode;
	meeting_type_id: string | null;
	/** E3: the call's host (null is Jafar); a request's is the type's default host. */
	host_member_id: string | null;
	/** The visitor's links stop working at this time (Jafar's deadline before the call). */
	change_until: string;
	can_change: boolean;
};

/**
 * E3: one of a booked call's hosts and whether they can take it at its time: `current` host, `free`, `busy` (a
 * call or Busy block then), `outside_hours` (not in their weekly hours), `no_access` (cannot change Leads & Deals)
 * or `removed` from the team.
 */
export type HostChoice = {
	member_id: string | null;
	name: string;
	state: 'current' | 'free' | 'busy' | 'outside_hours' | 'no_access' | 'removed';
};

export type HostChoices = {
	/** False once the call is over or closed, or for someone who cannot change calls. */
	can_change: boolean;
	host_member_id: string | null;
	choices: HostChoice[];
};

export const HOST_STATE_WORDS: Record<HostChoice['state'], string> = {
	current: 'Hosting now',
	free: 'Free then',
	busy: 'Busy then',
	outside_hours: 'Outside their hours',
	no_access: 'No Leads & Deals access',
	removed: 'No longer on the team'
};

/** What the visitor's link page shows: the booking and where to book again. */
export type ManagedBooking = Omit<
	BookingView,
	'visitor_email' | 'relationship_id' | 'entry_id' | 'meeting_type_id' | 'host_member_id'
>;

// --- Choices -------------------------------------------------------------------------------------------------

export const DURATION_CHOICES = [15, 20, 30, 45, 60, 90] as const;
export const INTERVAL_CHOICES = [10, 15, 20, 30, 45, 60, 90, 120] as const;
export const BUFFER_CHOICES = [0, 5, 10, 15, 30, 45, 60] as const;
/** Minimum notice, in minutes. */
export const NOTICE_CHOICES = [0, 60, 120, 240, 720, 1440, 2880, 4320, 10080] as const;
/** E2: how long before the call a visitor can still change or cancel, in minutes. */
export const CHANGE_DEADLINE_CHOICES = [0, 60, 120, 240, 720, 1440, 2880] as const;
export const HORIZON_CHOICES = [7, 14, 30, 60, 90, 180] as const;
/** E2b: when a visitor's reminder email can go, in minutes before the call; the database allows these only. */
export const VISITOR_REMINDER_CHOICES = [15, 30, 60, 120, 240, 1440, 2880] as const;
export const MAX_VISITOR_REMINDERS = 3;
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

export const LOCATION_WORDS: Record<LocationKind, string> = {
	phone: 'Phone call',
	zoom: 'Zoom video call'
};

/** E4a: the provider's own name, as "Add the Zoom link". */
export const VIDEO_PROVIDER_WORDS: Record<Exclude<LocationKind, 'phone'>, string> = {
	zoom: 'Zoom'
};

/** E4a: a video call still waiting for its joining link. */
export const videoPending = (booking: Pick<BookingView, 'location_kind' | 'video_join_url'>) =>
	booking.location_kind !== 'phone' && !booking.video_join_url;

/**
 * E4a: what the host's call panel shows about a booked call's video link. `can_change` is false once the call is
 * over or closed, or for someone who cannot change calls.
 */
export type CallVideoLink = {
	location_kind: Exclude<LocationKind, 'phone'>;
	video_join_url: string | null;
	video_link_source: 'provider' | 'custom' | null;
	can_change: boolean;
};

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

/** E3: what a meeting type's page sends; no id adds a type. */
export type MeetingTypeInput = Omit<MeetingType, 'id' | 'bookings_count' | 'description'> & {
	description: string | null;
};

/** E3: "jafar" or a teammate's id, as the hours routes name a person. */
export const personKey = (id: string | null) => id ?? 'jafar';

/** E3: a person's weekly ranges out of the settings. */
export const hoursOf = (settings: BookingSettings, id: string | null): BookingHours[] =>
	settings.hours
		.filter((range) => range.member_id === id)
		.map(({ weekday, start, end }) => ({ weekday, start, end }));

/** E3: "Mon–Fri, 9:00 – 17:00" style summary of weekly ranges; "No hours" when empty. */
export function hoursSummary(hours: BookingHours[]) {
	if (hours.length === 0) return 'No hours yet';
	const days = WEEKDAYS.filter((day) => hours.some((range) => range.weekday === day.value));
	const spans = new Set(hours.map((range) => `${range.start} – ${range.end}`));
	const dayWords =
		days.length === 7
			? 'Every day'
			: isRun(days.map((day) => WEEKDAYS.indexOf(day))) && days.length > 2
				? `${days[0].short}–${days[days.length - 1].short}`
				: days.map((day) => day.short).join(', ');
	return spans.size === 1 ? `${dayWords}, ${[...spans][0]}` : `${dayWords}, varied times`;
}

function isRun(indexes: number[]) {
	return indexes.every((value, index) => index === 0 || value === indexes[index - 1] + 1);
}
