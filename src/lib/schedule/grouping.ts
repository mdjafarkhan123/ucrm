import type { ScheduleFilters } from '$lib/schedule/filters';
import { splitDayVisits } from '$lib/schedule/layout';
import { visitDerivedStatus } from '$lib/schedule/status';
import type { ScheduleVisit } from '$lib/schedule/api';
import type { TeamMember } from '$lib/team/api';

// Turning a window's visits into what the workspace draws. It is here rather than in the page because it is
// ordinary logic with no markup in it: it can be tested directly, and Part 3's grids can reuse the same
// grouping when they replace the list.

/** Employee and status, applied to the rows already in hand. The window read is bounded, so this is cheap. */
export function filterVisits(
	visits: ScheduleVisit[],
	filters: Pick<ScheduleFilters, 'employee' | 'status'>,
	today: string
): ScheduleVisit[] {
	return visits.filter((visit) => {
		if (filters.employee === 'unassigned') {
			if (visit.assignee_ids.length > 0) return false;
		} else if (filters.employee !== 'all' && !visit.assignee_ids.includes(filters.employee)) {
			return false;
		}
		if (filters.status !== 'all' && visitDerivedStatus(visit, today) !== filters.status) {
			return false;
		}
		return true;
	});
}

// Every day's visits, looked up by the day. A grid draws a cell for every day in its window, the quiet ones
// included, so it asks by day rather than walking a list that would leave those days out.
export function bucketVisitsByDay(visits: ScheduleVisit[]): Map<string, ScheduleVisit[]> {
	const byDay = new Map<string, ScheduleVisit[]>();
	for (const visit of visits) {
		if (!visit.visit_date) continue;
		const bucket = byDay.get(visit.visit_date);
		if (bucket) bucket.push(visit);
		else byDay.set(visit.visit_date, [visit]);
	}
	return byDay;
}

// The order one date's work reads in when there is no time axis to place it on, as the Month cell and its
// full-day list have. Anytime first, because a day-long commitment frames the day, then the timed work in
// start order. Two visits starting at the same minute keep a stable order rather than swapping places on
// every refetch.
export function orderDayVisits(visits: ScheduleVisit[]): ScheduleVisit[] {
	const split = splitDayVisits(visits);
	const timed = [...split.timed]
		.sort((a, b) => a.start - b.start || a.visit.id.localeCompare(b.visit.id))
		.map((span) => span.visit);
	return [...split.anytime, ...timed];
}

/** Names by id, so a row can say who is going without searching the team for every visit it draws. */
export function indexEmployees(members: TeamMember[]) {
	return new Map(members.map((member) => [member.id, member]));
}
