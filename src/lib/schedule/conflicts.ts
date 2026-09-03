import { clockMinutes } from '$lib/schedule/layout';
import { weekdayOf, type WorkingWeek } from '$lib/schedule/hours';
import type { ScheduleProposal } from '$lib/schedule/drag';
import type { ScheduleVisit } from '$lib/schedule/api';

// The two warnings Version 1 gives before a move is saved.
//
// They advise; they never refuse. A contractor double-books on purpose often enough -- two people on one
// street, a quick drop-in between jobs -- that a calendar which blocks it is a calendar people work around.
// So this answers "is there anything you should know before you press Save" and stops there.
//
// Both answers come from what the page already holds: the visits of the window on screen and the confirmed
// weekly hours. Nothing here asks the server, and nothing here is stored.

export type ScheduleWarning =
	/** This employee already has timed work that overlaps the proposed slot. */
	| { kind: 'overlap'; employee_id: string; visit_ids: string[] }
	/** The proposed slot falls outside the business's confirmed hours for that weekday. */
	| { kind: 'outside_hours' }
	/** The business is closed that whole weekday. */
	| { kind: 'closed_day' };

export type WarningInput = {
	/** The visit being moved, so it never conflicts with itself. */
	visitId: string;
	proposal: ScheduleProposal;
	/** The visits already loaded for the window on screen. */
	visits: ScheduleVisit[];
	/** Null when the business has no confirmed weekly pattern, and then no hours warning is honest. */
	workingWeek: WorkingWeek | null;
};

export function scheduleWarnings(input: WarningInput): ScheduleWarning[] {
	const { proposal } = input;
	if (proposal.visit_date === null) return [];

	return [...overlapWarnings(input), ...hoursWarnings(proposal, input.workingWeek)];
}

// One warning per double-booked employee, not one per clash, because the sentence a dispatcher needs is
// "Sam is already booked", and the visits behind it belong in that same sentence.
function overlapWarnings({ visitId, proposal, visits }: WarningInput): ScheduleWarning[] {
	const start = clockMinutes(proposal.start_time);
	const end = clockMinutes(proposal.end_time);
	// An Anytime visit claims no hour of the day, so it can overlap nothing.
	if (start === null || end === null || proposal.assignee_ids.length === 0) return [];

	const clashesByEmployee = new Map<string, string[]>();

	for (const other of visits) {
		if (other.id === visitId) continue;
		if (other.completed_at !== null) continue;
		if (other.visit_date !== proposal.visit_date) continue;

		const otherStart = clockMinutes(other.start_time);
		const otherEnd = clockMinutes(other.end_time);
		if (otherStart === null || otherEnd === null || otherEnd <= otherStart) continue;
		// Touching ends are not an overlap: work that finishes at eleven and work that starts at eleven is a
		// full day, not a clash.
		if (otherStart >= end || otherEnd <= start) continue;

		for (const employeeId of other.assignee_ids) {
			if (!proposal.assignee_ids.includes(employeeId)) continue;
			const clashes = clashesByEmployee.get(employeeId);
			if (clashes) clashes.push(other.id);
			else clashesByEmployee.set(employeeId, [other.id]);
		}
	}

	return [...clashesByEmployee].map(([employee_id, visit_ids]) => ({
		kind: 'overlap' as const,
		employee_id,
		visit_ids
	}));
}

// Outside the confirmed hours means exactly that: no band of that weekday contains the whole proposed slot.
// A business with no confirmed weekly pattern gets no warning at all rather than being measured against a
// nine-to-five nobody agreed to.
function hoursWarnings(
	proposal: ScheduleProposal,
	workingWeek: WorkingWeek | null
): ScheduleWarning[] {
	if (!workingWeek || proposal.visit_date === null) return [];

	const bands = workingWeek.get(weekdayOf(proposal.visit_date)) ?? [];
	if (bands.length === 0) return [{ kind: 'closed_day' }];

	const start = clockMinutes(proposal.start_time);
	const end = clockMinutes(proposal.end_time);
	// Anytime work only has to fall on an open day; it claims no particular hour to check.
	if (start === null || end === null) return [];

	const inside = bands.some((band) => start >= band.start && end <= band.end);
	return inside ? [] : [{ kind: 'outside_hours' }];
}
