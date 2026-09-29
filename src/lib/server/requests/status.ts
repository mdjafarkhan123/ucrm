// Request status has two halves. Seven values are stored on the row; the three calendar ones — today,
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

import { calendarDay, calendarParts, localMidnight } from '$lib/server/time/calendar';

import type {
	DisplayRequestStatus,
	RequestScheduleState,
	StoredRequestStatus
} from '$lib/requests/statuses';

export type AssessmentScheduleFields = {
	starts_at: string | null;
	completed_at: string | null;
};

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
export function organizationDayRange(timezone: string, now = new Date()) {
	const { year, month, day } = calendarParts(now, timezone);
	return {
		day_start: localMidnight(year, month, day, timezone, now).toISOString(),
		day_end: localMidnight(year, month, day + 1, timezone, now).toISOString()
	};
}

// The Requests list's Status filter, as PostgREST or= branches over `request_list_rows`. It must pick
// exactly the rows `deriveRequestStatus` would badge with the chosen statuses, so it follows the same
// three steps: a finished request keeps its stored status; an open one with no live assessment keeps
// its stored status too; an open one with a live assessment reads its start time against today.
// Returns null when nothing is chosen, so the caller adds no filter at all.
const OPEN_STORED = 'status.in.(needs_approval,new,unscheduled)';

export function displayStatusFilter(
	statuses: readonly DisplayRequestStatus[],
	range: { day_start: string; day_end: string }
): string | null {
	const dayStart = `"${range.day_start}"`;
	const dayEnd = `"${range.day_end}"`;
	const branches = new Set<string>();
	for (const status of statuses) {
		switch (status) {
			case 'needs_approval':
				branches.add('and(status.eq.needs_approval,has_open_assessment.is.false)');
				break;
			case 'new':
				branches.add('and(status.eq.new,has_open_assessment.is.false)');
				break;
			case 'unscheduled':
				branches.add('and(status.eq.unscheduled,has_open_assessment.is.false)');
				branches.add(
					`and(${OPEN_STORED},has_open_assessment.is.true,assessment_starts_at.is.null)`
				);
				break;
			case 'today':
				branches.add(
					`and(${OPEN_STORED},has_open_assessment.is.true,assessment_starts_at.gte.${dayStart},assessment_starts_at.lt.${dayEnd})`
				);
				break;
			case 'upcoming':
				branches.add(
					`and(${OPEN_STORED},has_open_assessment.is.true,assessment_starts_at.gte.${dayEnd})`
				);
				break;
			case 'overdue':
				branches.add(
					`and(${OPEN_STORED},has_open_assessment.is.true,assessment_starts_at.lt.${dayStart})`
				);
				break;
			default:
				branches.add(`status.eq.${status}`);
		}
	}
	return branches.size > 0 ? [...branches].join(',') : null;
}
