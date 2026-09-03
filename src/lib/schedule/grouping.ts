import type { ScheduleFilters } from '$lib/schedule/filters';
import { splitDayVisits } from '$lib/schedule/layout';
import { visitDerivedStatus } from '$lib/schedule/status';
import type { ScheduleItem } from '$lib/schedule/items';
import type { TeamMember } from '$lib/team/api';

// Turning a window's items into what the workspace draws. It is here rather than in the page because it is
// ordinary logic with no markup in it: it can be tested directly, and the grids reuse the same grouping.
// A "visit" here is any calendar item -- a job visit or an assessment -- because employee and status narrow
// the same way for both, and a day cell buckets them together.

/** Employee and status, applied to the items already in hand. The window read is bounded, so this is cheap. */
export function filterVisits(
	items: ScheduleItem[],
	filters: Pick<ScheduleFilters, 'employee' | 'status'>,
	today: string
): ScheduleItem[] {
	return items.filter((item) => {
		if (filters.employee === 'unassigned') {
			if (item.assignee_ids.length > 0) return false;
		} else if (filters.employee !== 'all' && !item.assignee_ids.includes(filters.employee)) {
			return false;
		}
		if (filters.status !== 'all' && visitDerivedStatus(item, today) !== filters.status) {
			return false;
		}
		return true;
	});
}

// Every day's items, looked up by the day. A grid draws a cell for every day in its window, the quiet ones
// included, so it asks by day rather than walking a list that would leave those days out.
export function bucketVisitsByDay(items: ScheduleItem[]): Map<string, ScheduleItem[]> {
	const byDay = new Map<string, ScheduleItem[]>();
	for (const item of items) {
		if (!item.visit_date) continue;
		const bucket = byDay.get(item.visit_date);
		if (bucket) bucket.push(item);
		else byDay.set(item.visit_date, [item]);
	}
	return byDay;
}

// The order one date's work reads in when there is no time axis to place it on, as the Month cell and its
// full-day list have. Anytime first, because a day-long commitment frames the day, then the timed work in
// start order. Two items starting at the same minute keep a stable order rather than swapping places on
// every refetch.
export function orderDayVisits(items: ScheduleItem[]): ScheduleItem[] {
	const split = splitDayVisits(items);
	const timed = [...split.timed]
		.sort((a, b) => a.start - b.start || a.item.id.localeCompare(b.item.id))
		.map((span) => span.item);
	return [...split.anytime, ...timed];
}

/** Names by id, so a row can say who is going without searching the team for every visit it draws. */
export function indexEmployees(members: TeamMember[]) {
	return new Map(members.map((member) => [member.id, member]));
}
