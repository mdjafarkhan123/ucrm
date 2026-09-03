import type { ScheduleEmployeeFilter } from '$lib/schedule/filters';
import {
	visitClientLabel,
	visitPlaceLabel,
	visitWorkLabel
} from '$lib/schedule/labels';
import type { UnscheduledVisit } from '$lib/schedule/api';

// What the Unscheduled drawer does to the backlog before it draws it: narrow it by a search box and an
// assignment filter, and say how long each piece of work has been waiting. It is here, away from the markup,
// because it is ordinary logic with a right and a wrong answer that a test can pin down.

/** How many whole days ago a visit was created, from its creation day and the contractor's today. Never
 *  negative: a clock skew that puts creation "tomorrow" reads as today, not as waiting minus one day. */
export function waitingDays(createdDay: string, today: string): number {
	// Both are plain calendar days, compared as the UTC midnights they name -- the same day arithmetic the
	// window schema uses -- so no timezone can slide the count a day either way.
	const created = Date.parse(`${createdDay}T00:00:00Z`);
	const now = Date.parse(`${today}T00:00:00Z`);
	if (Number.isNaN(created) || Number.isNaN(now)) return 0;
	return Math.max(0, Math.round((now - created) / 86_400_000));
}

/** "Added today", "Waiting 1 day", "Waiting 12 days" -- the age a backlog card shows. */
export function backlogAgeLabel(createdDay: string, today: string): string {
	const days = waitingDays(createdDay, today);
	if (days === 0) return 'Added today';
	return days === 1 ? 'Waiting 1 day' : `Waiting ${days} days`;
}

// The searchable text of one backlog visit: who it is for, what the work is, and where. Assembled once so the
// filter matches the same words the card actually shows.
function searchText(visit: UnscheduledVisit): string {
	return [visitClientLabel(visit), visitWorkLabel(visit), visitPlaceLabel(visit)]
		.filter(Boolean)
		.join(' ')
		.toLowerCase();
}

/** The search box and the assignment filter, applied to the backlog already in hand. The read is bounded, so
 *  this is cheap -- a filter change re-uses the rows instead of asking the server again. */
export function filterBacklog(
	visits: UnscheduledVisit[],
	filters: { query: string; employee: ScheduleEmployeeFilter }
): UnscheduledVisit[] {
	const needle = filters.query.trim().toLowerCase();
	return visits.filter((visit) => {
		if (filters.employee === 'unassigned') {
			if (visit.assignee_ids.length > 0) return false;
		} else if (filters.employee !== 'all' && !visit.assignee_ids.includes(filters.employee)) {
			return false;
		}
		if (needle && !searchText(visit).includes(needle)) return false;
		return true;
	});
}
