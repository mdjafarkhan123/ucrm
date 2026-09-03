import { layoutTimedVisits, splitDayVisits, type TimedVisitBlock } from '$lib/schedule/layout';
import type { ScheduleItem } from '$lib/schedule/items';
import type { ScheduleEmployeeFilter } from '$lib/schedule/filters';
import type { TeamMember } from '$lib/team/api';

// One day, read as rows of people rather than as a column of hours.
//
// This is the dispatch question: who is doing what, and where are the gaps. So the row is the unit, the
// unassigned pile is always the first one, and a person with an empty day still gets a row -- the emptiness
// is the answer. A visit two people share is placed in both of their rows; it stays one visit, drawn twice,
// because a workload that only counts once is a lie about somebody's day.

/** A person's row, or the pile nobody has picked up yet. */
export type DayRowKind = 'unassigned' | 'employee';

export type DayRow = {
	/** 'unassigned', or the employee's id. Stable, so a row keeps its identity across refetches. */
	key: string;
	kind: DayRowKind;
	/** Null for the unassigned row, and for an assignee who is no longer on the assignable list. */
	employee: TeamMember | null;
	name: string;
	/** Dated, no clock time. These sit in the row's own Anytime column, never on the time axis. */
	anytime: ScheduleItem[];
	blocks: TimedVisitBlock[];
	/** How many visits deep this row ever stacks. At least one, so an empty row still has a height. */
	lanes: number;
	count: number;
};

export const UNASSIGNED_ROW_KEY = 'unassigned';

/** Somebody is on this visit who is not on the assignable list -- deactivated, or hidden from this reader.
 * Their work still gets a row, because a visit that quietly vanishes from the board is worse than a row
 * with an incomplete name on it. */
const UNLISTED_NAME = 'Unlisted team member';

export function buildDayRows(
	items: ScheduleItem[],
	team: TeamMember[],
	employeeFilter: ScheduleEmployeeFilter
): DayRow[] {
	const byRow = new Map<string, ScheduleItem[]>();
	const push = (key: string, item: ScheduleItem) => {
		const bucket = byRow.get(key);
		if (bucket) bucket.push(item);
		else byRow.set(key, [item]);
	};

	for (const item of items) {
		if (item.assignee_ids.length === 0) push(UNASSIGNED_ROW_KEY, item);
		else for (const id of item.assignee_ids) push(id, item);
	}

	const teamById = new Map(team.map((member) => [member.id, member]));

	// Unassigned leads, then the team in the order the roster arrived in, then anybody the roster does not
	// account for. The filter narrows which of those rows are drawn at all, the way the team filter does on
	// every dispatch board: picking one person means looking at one person, not dimming everybody else.
	const keys: string[] = [];
	if (employeeFilter === 'all' || employeeFilter === UNASSIGNED_ROW_KEY) {
		keys.push(UNASSIGNED_ROW_KEY);
	}
	if (employeeFilter !== UNASSIGNED_ROW_KEY) {
		for (const member of team) {
			if (employeeFilter === 'all' || employeeFilter === member.id) keys.push(member.id);
		}
		for (const key of byRow.keys()) {
			if (key === UNASSIGNED_ROW_KEY || teamById.has(key)) continue;
			if (employeeFilter === 'all' || employeeFilter === key) keys.push(key);
		}
	}

	return keys.map((key) => {
		const rowVisits = byRow.get(key) ?? [];
		const split = splitDayVisits(rowVisits);
		const blocks = layoutTimedVisits(split.timed);
		const employee = teamById.get(key) ?? null;
		return {
			key,
			kind: key === UNASSIGNED_ROW_KEY ? ('unassigned' as const) : ('employee' as const),
			employee,
			name:
				key === UNASSIGNED_ROW_KEY
					? 'Unassigned'
					: (employee?.full_name ?? (employee ? 'Team member' : UNLISTED_NAME)),
			anytime: split.anytime,
			blocks,
			lanes: Math.max(1, ...blocks.map((block) => block.columns)),
			count: rowVisits.length
		};
	});
}
