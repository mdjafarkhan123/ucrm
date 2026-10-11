import { parseDate } from '@internationalized/date';
import { formatCalendarDay } from '$lib/schedule/labels';
import { eachDayInWindow, shiftScheduleDate } from '$lib/schedule/filters';

// Timesheets (docs/time-clock-behavior-contract.md § Timesheets page). The page reads one row per person
// for a day or a week; a person's entries are a second read, made when their row is opened.

export type TimesheetSpan = 'day' | 'week';

export type TimesheetRunning = {
	kind: 'visit' | 'general';
	job_id: string | null;
	job_number: number | null;
	started_at: string;
	/** The business day the timer started on. Its hours belong to that day. */
	started_on: string;
	/** Running more than 12 hours: flagged so someone checks it (plan § Forgotten timers). */
	long_running: boolean;
};

export type TimesheetPerson = {
	user_id: string;
	name: string | null;
	avatar_url: string | null;
	status: 'pending' | 'active' | 'deactivated' | 'removed';
	is_me: boolean;
	/** Recorded minutes per business day, YYYY-MM-DD. A day with none is absent. */
	days: Record<string, number>;
	total_minutes: number;
	entry_count: number;
	overlap_count: number;
	/** What they are on the clock for now, whatever day it started. Not in the totals until it stops. */
	running: TimesheetRunning | null;
};

export type TimesheetSummary = {
	span: TimesheetSpan;
	from: string;
	to: string;
	timezone: string;
	today: string;
	server_now: string;
	/** Everyone's hours (time.track_team), or only the reader's own. */
	can_view_team: boolean;
	people: TimesheetPerson[];
};

export type TimesheetEntry = {
	/** Null for a running timer, which is not an entry until it stops. */
	id: string | null;
	kind: 'job' | 'general';
	is_running: boolean;
	source: 'manual' | 'timer';
	started_at: string;
	/** Null while the timer runs. */
	ended_at: string | null;
	started_on: string;
	/** Null while the timer runs. */
	minutes: number | null;
	notes: string | null;
	/** Shares a minute or more with another of this person's entries. */
	overlaps: boolean;
	long_running: boolean;
	/** The Job the hours are on. Title and client are null when the reader may not open it. */
	job: {
		id: string;
		number: number;
		visible: boolean;
		title: string | null;
		client_name: string | null;
	} | null;
	visit_date: string | null;
};

export type TimesheetEntries = {
	user_id: string;
	from: string;
	to: string;
	timezone: string;
	server_now: string;
	entries: TimesheetEntry[];
	/** More entries exist than were sent. A guard, never reached by a real week. */
	truncated: boolean;
};

async function readOrThrow<T>(response: Response, fallback: string): Promise<T> {
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		const error = new Error(result.error ?? fallback) as Error & { status?: number };
		error.status = response.status;
		throw error;
	}
	return response.json();
}

/** Every Timesheets read. A timer starting or stopping, or hours typed on a Job, refreshes them all. */
export const timesheetsKey = ['time-clock', 'timesheets'] as const;

// A missing date means "today in the business", which only the server knows, so it is its own key.
export function timesheetSummaryKey(span: TimesheetSpan, date: string | null) {
	return [...timesheetsKey, 'summary', span, date ?? 'today'] as const;
}

export function timesheetEntriesKey(userId: string, from: string, to: string) {
	return [...timesheetsKey, 'entries', userId, from, to] as const;
}

export async function fetchTimesheetSummary(
	span: TimesheetSpan,
	date: string | null
): Promise<TimesheetSummary> {
	const params = new URLSearchParams({ span });
	if (date) params.set('date', date);
	const response = await fetch(`/api/time-clock/timesheets?${params}`);
	return readOrThrow(response, 'Timesheets could not be loaded.');
}

export async function fetchTimesheetEntries(
	userId: string,
	from: string,
	to: string
): Promise<TimesheetEntries> {
	const params = new URLSearchParams({ user_id: userId, from, to });
	const response = await fetch(`/api/time-clock/timesheets/entries?${params}`);
	return readOrThrow(response, 'These hours could not be loaded.');
}

// --- The page's memory: the URL --------------------------------------------------------------------------

export type TimesheetFilters = {
	span: TimesheetSpan;
	/** The anchor day, or null for today in the business. */
	date: string | null;
	/** Chosen people. Empty means everyone the reader may see. */
	people: string[];
};

const ISO_DAY = /^\d{4}-\d{2}-\d{2}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function readDay(raw: string | null): string | null {
	if (!raw || !ISO_DAY.test(raw)) return null;
	try {
		return parseDate(raw).toString();
	} catch {
		return null;
	}
}

export function readTimesheetFilters(params: URLSearchParams): TimesheetFilters {
	const span = params.get('view') === 'day' ? 'day' : 'week';
	const people = (params.get('people') ?? '')
		.split(',')
		.filter((id) => UUID.test(id))
		.slice(0, 200);
	return { span, date: readDay(params.get('date')), people: [...new Set(people)] };
}

// Only what differs from the default is written, so a plain /timesheets link stays plain and opens on this
// week.
export function timesheetFilterParams(filters: TimesheetFilters) {
	const params = new URLSearchParams();
	if (filters.span !== 'week') params.set('view', filters.span);
	if (filters.date) params.set('date', filters.date);
	if (filters.people.length > 0) params.set('people', filters.people.join(','));
	return params;
}

/** The anchor one whole window back or forward: a day in Day, a week in Week. */
export function shiftTimesheetDate(date: string, span: TimesheetSpan, direction: -1 | 1) {
	return shiftScheduleDate(date, span, direction);
}

export function timesheetDays(summary: Pick<TimesheetSummary, 'from' | 'to'>) {
	return eachDayInWindow({ from: summary.from, to: summary.to });
}

// The window in words, as the Schedule writes it: "Monday, October 5, 2026" or "Oct 4 – Oct 10, 2026".
export function timesheetRangeLabel(span: TimesheetSpan, from: string, to: string) {
	if (span === 'day') {
		return formatCalendarDay(from, {
			weekday: 'long',
			month: 'long',
			day: 'numeric',
			year: 'numeric'
		});
	}
	const sameYear = from.slice(0, 4) === to.slice(0, 4);
	const start = formatCalendarDay(from, {
		month: 'short',
		day: 'numeric',
		...(sameYear ? {} : { year: 'numeric' })
	});
	const end = formatCalendarDay(to, { month: 'short', day: 'numeric', year: 'numeric' });
	return `${start} – ${end}`;
}

/** A clock time in the business's time zone, where the hours were worked: "8:00 AM". */
export function clockTime(instant: string, timezone: string) {
	return new Intl.DateTimeFormat('en-US', {
		timeZone: timezone,
		hour: 'numeric',
		minute: '2-digit'
	}).format(new Date(instant));
}

/** What an entry was for, in a few words: "Job #12 · Spring cleanup", "Job #12", or "General". */
export function entryPurpose(entry: Pick<TimesheetEntry, 'kind' | 'job'>) {
	if (entry.kind === 'general' || !entry.job) return 'General';
	const number = `Job #${entry.job.number}`;
	return entry.job.title ? `${number} · ${entry.job.title}` : number;
}

/** The people a manager has narrowed the page to, or everyone when none are chosen. */
export function visiblePeople(people: TimesheetPerson[], chosen: string[]) {
	if (chosen.length === 0) return people;
	const wanted = new Set(chosen);
	return people.filter((person) => wanted.has(person.user_id));
}

/** Minutes per day across the people shown, for the footer of the week. */
export function dayTotals(people: TimesheetPerson[], days: string[]) {
	return days.map((day) => people.reduce((sum, person) => sum + (person.days[day] ?? 0), 0));
}

export function personName(person: Pick<TimesheetPerson, 'name'>) {
	return person.name ?? 'Unnamed team member';
}

/**
 * What needs checking among the people shown (plan § Timesheets page, Warnings), one sentence each:
 * entries that overlap, and timers running more than 12 hours. One person is named; more are counted.
 */
export function timesheetWarnings(people: TimesheetPerson[]) {
	const warnings: string[] = [];
	const overlapping = people.filter((person) => person.overlap_count > 0);
	if (overlapping.length === 1) {
		const [person] = overlapping;
		warnings.push(
			person.is_me
				? 'You have entries that overlap.'
				: `${personName(person)} has entries that overlap.`
		);
	} else if (overlapping.length > 1) {
		warnings.push(`${overlapping.length} people have entries that overlap.`);
	}

	const longRunning = people.filter((person) => person.running?.long_running);
	if (longRunning.length === 1) {
		const [person] = longRunning;
		warnings.push(
			person.is_me
				? 'Your timer has run over 12 hours.'
				: `${personName(person)}'s timer has run over 12 hours.`
		);
	} else if (longRunning.length > 1) {
		warnings.push(`${longRunning.length} timers have run over 12 hours.`);
	}
	return warnings;
}
