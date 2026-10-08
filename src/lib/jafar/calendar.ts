import type { QueryClient } from '@tanstack/svelte-query';
import { fromAbsolute, parseDate, toCalendarDateTime } from '@internationalized/date';
import type { DealStage } from './deals';
import { jafarCalendarKey, jafarHomeKey, jafarLeadsKey } from './query-keys';

// Jafar business management C2: the Business Management calendar -- sales calls, Busy blocks and dated next
// actions -- and the reminders they carry, in the words the page, the dialogs and the API share. A reminder is a
// channel and a "how long before", as in Google Calendar; defaults live in My preferences and each call or next
// action can carry its own.

export type ReminderChannel = 'in_app' | 'email';
/** For anything with a time. */
export type TimedReminder = { channel: ReminderChannel; minutes_before: number };
/** For a next action with only a day: so many days before, at a time of day ("09:00"). */
export type DayReminder = { channel: ReminderChannel; days_before: number; at: string };
export type ReminderRule = TimedReminder | DayReminder;

export type ReminderDefaults = {
	call: TimedReminder[];
	follow_up_day: DayReminder[];
	follow_up_timed: TimedReminder[];
};

/** At most this many reminders on one call or next action. */
export const MAX_REMINDERS = 5;
export const MAX_MINUTES_BEFORE = 4 * 7 * 24 * 60;
export const MAX_DAYS_BEFORE = 28;

export type CallStatus = 'scheduled' | 'held' | 'no_show' | 'cancelled';
export type CallOutcome = Exclude<CallStatus, 'scheduled'>;

export const CALL_OUTCOME_LABELS: Record<CallOutcome, string> = {
	held: 'Held',
	no_show: "They didn't show",
	cancelled: 'Cancelled'
};

export type CalendarEntry = {
	id: string;
	kind: 'call' | 'busy';
	relationship_id: string | null;
	business_name: string | null;
	title: string | null;
	starts_at: string;
	ends_at: string;
	status: CallStatus;
	owner_member_id: string | null;
	deal_stage: DealStage | null;
};

export type CalendarFollowUp = {
	id: string;
	business_name: string;
	next_action: string;
	due_on: string;
	due_at: string | null;
	first_contact: boolean;
	deal_stage: DealStage | null;
};

export type CalendarWindowData = {
	entries: CalendarEntry[];
	follow_ups: CalendarFollowUp[];
	/** More than the calendar shows; narrow the view. */
	truncated: boolean;
};

export type CalendarEntryDetail = CalendarEntry & {
	contact_name: string | null;
	notes: string | null;
	outcome_at: string | null;
	outcome_by_email: string | null;
	reminders: TimedReminder[] | null;
	is_next_action: boolean;
};

export type UnclosedCall = {
	id: string;
	relationship_id: string;
	business_name: string;
	title: string | null;
	starts_at: string;
	ends_at: string;
};

export type CalendarPreferences = {
	/** Null until Jafar has a time zone saved; the browser's is used and saved with his first booking. */
	time_zone: string | null;
	reminder_defaults: ReminderDefaults;
};

// --- Words ---------------------------------------------------------------------------------------------------------

const CHANNEL_WORDS: Record<ReminderChannel, string> = { in_app: 'Alert', email: 'Email' };

function amount(value: number, unit: string) {
	return `${value} ${unit}${value === 1 ? '' : 's'}`;
}

/** "45 minutes", "1 hour", "1 day", "2 weeks" -- whichever unit divides evenly, largest first. */
export function durationWords(minutes: number): string {
	if (minutes === 0) return 'At the time';
	if (minutes % (7 * 24 * 60) === 0) return amount(minutes / (7 * 24 * 60), 'week');
	if (minutes % (24 * 60) === 0) return amount(minutes / (24 * 60), 'day');
	if (minutes % 60 === 0) return amount(minutes / 60, 'hour');
	return amount(minutes, 'minute');
}

/** 09:00 -> 9am, 14:30 -> 2:30pm. */
export function clockWords(at: string): string {
	const [hour, minute] = at.split(':').map(Number);
	const suffix = hour < 12 ? 'am' : 'pm';
	const twelve = hour % 12 === 0 ? 12 : hour % 12;
	return minute === 0
		? `${twelve}${suffix}`
		: `${twelve}:${String(minute).padStart(2, '0')}${suffix}`;
}

/** "Email 1 day before", "Alert at the time", "Alert on the day at 9am", "Email 2 days before at 5pm". */
export function reminderLabel(rule: ReminderRule): string {
	const channel = CHANNEL_WORDS[rule.channel];
	if ('minutes_before' in rule) {
		return rule.minutes_before === 0
			? `${channel} at the time`
			: `${channel} ${durationWords(rule.minutes_before)} before`;
	}
	const when = rule.days_before === 0 ? 'on the day' : `${amount(rule.days_before, 'day')} before`;
	return `${channel} ${when} at ${clockWords(rule.at)}`;
}

// --- Time zones ------------------------------------------------------------------------------------------------------

export function browserTimeZone(): string {
	return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
}

/** Where an instant falls in a time zone: its day and minutes past midnight. */
export function zonedPlace(iso: string, zone: string): { day: string; minutes: number } {
	const zoned = fromAbsolute(Date.parse(iso), zone);
	return { day: zoned.toString().slice(0, 10), minutes: zoned.hour * 60 + zoned.minute };
}

/** The instant a day and minutes past midnight name in a time zone, as ISO text. */
export function zonedInstant(day: string, minutes: number, zone: string): string {
	const local = toCalendarDateTime(parseDate(day)).add({ minutes });
	return local.toDate(zone).toISOString();
}

/** "HH:MM" from minutes past midnight. */
export function clockText(minutes: number): string {
	const hour = Math.floor(minutes / 60);
	return `${String(hour).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
}

// --- Browser side ----------------------------------------------------------------------------------------------------

export function calendarWindowKey(from: string, to: string, zone: string) {
	return [...jafarCalendarKey, 'window', from, to, zone] as const;
}
export function calendarEntryKey(id: string) {
	return [...jafarCalendarKey, 'entry', id] as const;
}
export const calendarPreferencesKey = [...jafarCalendarKey, 'preferences'] as const;
export const calendarUnclosedKey = [...jafarCalendarKey, 'unclosed'] as const;

async function read<T>(path: string, failure: string): Promise<T> {
	const response = await fetch(path);
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw new Error(result.error ?? failure);
	return result as T;
}

export function fetchCalendarWindow(from: string, to: string, zone: string) {
	const query = new URLSearchParams({ from, to, zone });
	return read<CalendarWindowData>(
		`/api/jafar/calendar?${query}`,
		'The calendar could not be loaded.'
	);
}

export function fetchCalendarEntry(id: string) {
	return read<CalendarEntryDetail>(
		`/api/jafar/calendar/entries/${encodeURIComponent(id)}`,
		'This could not be loaded.'
	);
}

export function fetchCalendarPreferences() {
	return read<CalendarPreferences>(
		'/api/jafar/calendar/preferences',
		'Your calendar choices could not be loaded.'
	);
}

export function fetchUnclosedCalls() {
	return read<{ count: number; calls: UnclosedCall[] }>(
		'/api/jafar/calendar/unclosed',
		'Calls waiting for an outcome could not be loaded.'
	);
}

/** After any change to a call, a Busy block, a next action or the preferences: the calendar, the home, the Leads. */
export function refreshCalendar(queryClient: QueryClient) {
	return Promise.all([
		queryClient.invalidateQueries({ queryKey: jafarCalendarKey }),
		queryClient.invalidateQueries({ queryKey: jafarHomeKey }),
		queryClient.invalidateQueries({ queryKey: jafarLeadsKey })
	]);
}

// --- Placing things on the calendar ----------------------------------------------------------------------------------

/** One thing drawn on the calendar: a call, a Busy block, or a dated next action. */
export type CalendarItem =
	| { id: string; kind: 'call' | 'busy'; entry: CalendarEntry }
	| { id: string; kind: 'follow_up'; followUp: CalendarFollowUp };

/** How long a follow-up with a time is drawn; it has no end of its own. */
export const FOLLOW_UP_DRAWN_MINUTES = 30;

const MINUTES_IN_DAY = 24 * 60;

export type CalendarDay = {
	/** Follow-ups with only a day: the grid's top lane. */
	anytime: CalendarItem[];
	timed: { item: CalendarItem; start: number; end: number }[];
};

/**
 * Each day's items in the calendar's time zone. Something running past midnight is drawn on both days, cut at
 * midnight, as Google Calendar does; a cancelled call is not drawn.
 */
export function placeCalendarItems(
	data: CalendarWindowData,
	zone: string
): Map<string, CalendarDay> {
	const days = new Map<string, CalendarDay>();
	const dayOf = (day: string) => {
		let found = days.get(day);
		if (!found) {
			found = { anytime: [], timed: [] };
			days.set(day, found);
		}
		return found;
	};

	for (const entry of data.entries) {
		if (entry.status === 'cancelled') continue;
		const item: CalendarItem = { id: `entry:${entry.id}`, kind: entry.kind, entry };
		const start = zonedPlace(entry.starts_at, zone);
		const end = zonedPlace(entry.ends_at, zone);
		let day = start.day;
		// At most two days: nothing lasts longer than 24 hours.
		for (let guard = 0; guard < 3; guard += 1) {
			const from = day === start.day ? start.minutes : 0;
			const to = day === end.day ? end.minutes : MINUTES_IN_DAY;
			if (to > from) dayOf(day).timed.push({ item, start: from, end: to });
			if (day === end.day) break;
			day = parseDate(day).add({ days: 1 }).toString();
		}
	}

	for (const followUp of data.follow_ups) {
		const item: CalendarItem = { id: `follow-up:${followUp.id}`, kind: 'follow_up', followUp };
		if (!followUp.due_at) {
			dayOf(followUp.due_on).anytime.push(item);
			continue;
		}
		const place = zonedPlace(followUp.due_at, zone);
		dayOf(place.day).timed.push({
			item,
			start: place.minutes,
			end: Math.min(MINUTES_IN_DAY, place.minutes + FOLLOW_UP_DRAWN_MINUTES)
		});
	}
	return days;
}

/** A day's items in reading order -- the month cell and the phone's day list: day-only follow-ups, then by time. */
export function orderCalendarDay(day: CalendarDay | undefined): CalendarItem[] {
	if (!day) return [];
	return [
		...day.anytime,
		...[...day.timed].sort((a, b) => a.start - b.start || a.end - b.end).map((span) => span.item)
	];
}

/** "9am", "2:30pm" from minutes past midnight. */
export function minutesWords(minutes: number): string {
	return clockWords(clockText(minutes % MINUTES_IN_DAY));
}

/** What a card or a list row calls an item. */
export function calendarItemTitle(item: CalendarItem): string {
	if (item.kind === 'follow_up') return item.followUp.next_action;
	if (item.kind === 'busy') return item.entry.title ?? 'Busy';
	return item.entry.title ?? `Call with ${item.entry.business_name}`;
}
