// Request status has two halves. Six values are stored on the row; the three calendar ones — today,
// upcoming, overdue — are worked out from the assessment's start time every time a request is read.
// Storing them would need a nightly job per timezone and rows would be wrong in between.

// The status list itself lives in `$lib/requests/statuses.ts` so the browser can read it too. Re-exported
// here because the server side of the app thinks of statuses and the derivation rule as one thing.
export {
	STORED_REQUEST_STATUSES,
	REQUEST_SCHEDULE_STATES,
	DISPLAY_REQUEST_STATUSES
} from '$lib/requests/statuses';
export type {
	StoredRequestStatus,
	RequestScheduleState,
	DisplayRequestStatus
} from '$lib/requests/statuses';

import type {
	DisplayRequestStatus,
	RequestScheduleState,
	StoredRequestStatus
} from '$lib/requests/statuses';

export type AssessmentScheduleFields = {
	starts_at: string | null;
	completed_at: string | null;
};

// en-CA gives YYYY-MM-DD, so two calendar days can be compared as plain strings.
function calendarDay(value: Date, timezone: string) {
	return new Intl.DateTimeFormat('en-CA', {
		timeZone: timezone,
		year: 'numeric',
		month: '2-digit',
		day: '2-digit'
	}).format(value);
}

// Compared by calendar day, not by the clock: an assessment booked for 9am today still reads as "today"
// at 5pm, which is what the office expects to see.
export function deriveScheduleState(
	startsAt: string,
	timezone: string,
	now = new Date()
): RequestScheduleState {
	const start = calendarDay(new Date(startsAt), timezone);
	const today = calendarDay(now, timezone);
	if (start === today) return 'today';
	return start > today ? 'upcoming' : 'overdue';
}

export function deriveRequestStatus(
	storedStatus: string,
	assessment: AssessmentScheduleFields | null,
	timezone: string,
	now = new Date()
): DisplayRequestStatus {
	// A finished or closed request keeps its own status. The calendar has nothing left to say about it.
	if (
		storedStatus === 'assessment_completed' ||
		storedStatus === 'completed' ||
		storedStatus === 'converted' ||
		storedStatus === 'archived'
	) {
		return storedStatus as StoredRequestStatus;
	}
	if (!assessment || assessment.completed_at) return storedStatus as StoredRequestStatus;
	if (!assessment.starts_at) return 'unscheduled';
	return deriveScheduleState(assessment.starts_at, timezone, now);
}

// The counts query buckets today / upcoming / overdue in the database, so it needs to know where today
// starts and ends. That answer stays here, next to the rule it belongs to, and the database is only ever
// handed two instants. A second copy of the timezone rule in SQL would drift from this one.
const OFFSET_FORMAT_OPTIONS: Intl.DateTimeFormatOptions = {
	year: 'numeric',
	month: '2-digit',
	day: '2-digit',
	hour: '2-digit',
	minute: '2-digit',
	second: '2-digit',
	hourCycle: 'h23'
};

// How far the timezone runs ahead of UTC at one particular instant. Read off the formatted local clock,
// because that is the only thing Intl will tell us, and the answer changes twice a year.
function offsetMilliseconds(at: Date, timezone: string) {
	const parts = new Intl.DateTimeFormat('en-US', {
		timeZone: timezone,
		...OFFSET_FORMAT_OPTIONS
	}).formatToParts(at);
	const read = (type: Intl.DateTimeFormatPartTypes) =>
		Number(parts.find((part) => part.type === type)?.value ?? '0');
	const asIfUtc = Date.UTC(
		read('year'),
		read('month') - 1,
		read('day'),
		read('hour'),
		read('minute'),
		read('second')
	);
	// Milliseconds are not in the formatted parts, so compare whole seconds on both sides.
	return asIfUtc - Math.floor(at.getTime() / 1000) * 1000;
}

// Local midnight, converted back to a real instant. The offset is read twice: the first guess uses the
// offset happening now, the second uses the offset at the guessed midnight, which is what fixes the two
// days a year when the clocks change between the two.
function localMidnight(year: number, month: number, day: number, timezone: string, now: Date) {
	const midnightAsIfUtc = Date.UTC(year, month - 1, day);
	const firstGuess = new Date(midnightAsIfUtc - offsetMilliseconds(now, timezone));
	return new Date(midnightAsIfUtc - offsetMilliseconds(firstGuess, timezone));
}

export function organizationDayRange(timezone: string, now = new Date()) {
	const [year, month, day] = calendarDay(now, timezone).split('-').map(Number);
	return {
		day_start: localMidnight(year, month, day, timezone, now).toISOString(),
		// Date.UTC rolls day 32 into the next month on its own, so month ends need no special case.
		day_end: localMidnight(year, month, day + 1, timezone, now).toISOString()
	};
}
