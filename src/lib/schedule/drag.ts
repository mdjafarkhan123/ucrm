import { parseDate } from '@internationalized/date';
import { clockMinutes, DEFAULT_VISIT_MINUTES, MINUTES_IN_DAY } from '$lib/schedule/layout';

// Turning a drag into a proposed schedule.
//
// Every calendar that lets you drag an appointment does the same three sums: where the pointer landed on the
// time axis, what the appointment would become there, and what actually changed. They live here, away from
// the markup, because Week drags down a day column and Day drags across an employee row from the same
// numbers -- and because a wrong sum here silently moves somebody's work to the wrong hour.
//
// Nothing in this file writes. It only describes the proposal the person is about to be shown.

/** Drags land on quarter hours, the granularity a dispatcher actually books in. */
export const SNAP_MINUTES = 15;

/** No drag may squash a visit below this. Resizing to nothing is not a schedule. */
export const MIN_VISIT_MINUTES = 15;

/** The schedule half of a visit -- the only part a drag touches. */
export type VisitSchedule = {
	visit_date: string | null;
	/** As the database returns it, 'HH:MM:SS'. */
	start_time: string | null;
	end_time: string | null;
	all_day: boolean;
	assignee_ids: string[];
};

/** A proposed schedule, in the shape the visit endpoint takes: times as 'HH:MM'. */
export type ScheduleProposal = {
	visit_date: string | null;
	start_time: string | null;
	end_time: string | null;
	all_day: boolean;
	assignee_ids: string[];
};

/** Rounds to the nearest quarter hour and never leaves the day. */
export function snapMinutes(minutes: number, snap: number = SNAP_MINUTES): number {
	const snapped = Math.round(minutes / snap) * snap;
	return Math.max(0, Math.min(MINUTES_IN_DAY, snapped));
}

/** Where a pointer sits on a time axis, given how many pixels one minute takes. */
export function minutesFromOffset(offsetPx: number, pxPerMinute: number): number {
	if (!Number.isFinite(pxPerMinute) || pxPerMinute <= 0) return 0;
	return snapMinutes(offsetPx / pxPerMinute);
}

/** 870 becomes '14:30'. The wire format is HH:MM; seconds are the database's business, not the form's. */
export function formatClock(minutes: number): string {
	const whole = Math.max(0, Math.min(MINUTES_IN_DAY - 1, Math.round(minutes)));
	const hour = Math.floor(whole / 60);
	const minute = whole % 60;
	return `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
}

// How long the visit is meant to take. A missing or backwards end is read as the default hour, the same
// reading the grid draws it with, so a drag never quietly changes a duration it could not see.
export function visitDurationMinutes(visit: VisitSchedule): number {
	const start = clockMinutes(visit.start_time);
	const end = clockMinutes(visit.end_time);
	if (start === null) return DEFAULT_VISIT_MINUTES;
	if (end === null || end <= start) return DEFAULT_VISIT_MINUTES;
	return end - start;
}

/** Where a drag was released. A null start means the Anytime lane -- the day without a clock time. */
export type DropTarget = {
	day: string;
	startMinutes: number | null;
	/** Only set when the drop crossed employee rows on the Day board. */
	assigneeIds?: string[];
};

// The visit as it would be at the drop point. Duration is carried across unchanged, so moving a two-hour
// visit to Thursday keeps it two hours; only a resize changes that. A visit dropped so late that it would
// run past midnight is pulled back to end at midnight rather than being clipped or spilling into the next
// day, which this campaign does not schedule across.
export function proposeMove(visit: VisitSchedule, target: DropTarget): ScheduleProposal {
	const assignee_ids = target.assigneeIds ?? visit.assignee_ids;

	if (target.startMinutes === null) {
		return {
			visit_date: target.day,
			start_time: null,
			end_time: null,
			all_day: true,
			assignee_ids
		};
	}

	const duration = Math.min(visitDurationMinutes(visit), MINUTES_IN_DAY);
	const start = Math.min(snapMinutes(target.startMinutes), MINUTES_IN_DAY - duration);
	return {
		visit_date: target.day,
		start_time: formatClock(start),
		end_time: formatClock(start + duration),
		all_day: false,
		assignee_ids
	};
}

// Dragging the bottom edge. The start never moves, and the visit cannot be squashed below a quarter hour or
// pushed past midnight. An Anytime visit has no edge to drag, so it comes back unchanged.
export function proposeResize(visit: VisitSchedule, endMinutes: number): ScheduleProposal {
	const start = clockMinutes(visit.start_time);
	if (visit.visit_date === null || start === null) return toProposal(visit);

	const end = Math.max(
		start + MIN_VISIT_MINUTES,
		Math.min(snapMinutes(endMinutes), MINUTES_IN_DAY)
	);
	return {
		visit_date: visit.visit_date,
		start_time: formatClock(start),
		end_time: formatClock(end),
		all_day: false,
		assignee_ids: visit.assignee_ids
	};
}

/** Reassignment with no move: the same slot, a different crew. */
export function proposeAssignment(visit: VisitSchedule, assigneeIds: string[]): ScheduleProposal {
	return { ...toProposal(visit), assignee_ids: assigneeIds };
}

// --- Creating from empty space ------------------------------------------------------------------------

// A brand-new visit's schedule as an empty-space gesture describes it. It carries no crew -- a new visit
// starts unassigned, and the job's own defaults are the person's next choice -- and no title or
// instructions, which the create form collects before anything is written.
export type NewVisitDraft = {
	visit_date: string;
	start_time: string | null;
	end_time: string | null;
	all_day: boolean;
};

// A single click on an empty timed slot. The visit opens at that quarter hour with the Version 1 one-hour
// default, pulled back so it never runs past midnight, exactly the way a dropped visit is. A click low
// enough that a whole hour would not fit is anchored so the hour still lands inside the day.
export function draftFromClick(day: string, startMinutes: number): NewVisitDraft {
	const start = Math.min(snapMinutes(startMinutes), MINUTES_IN_DAY - DEFAULT_VISIT_MINUTES);
	return {
		visit_date: day,
		start_time: formatClock(start),
		end_time: formatClock(start + DEFAULT_VISIT_MINUTES),
		all_day: false
	};
}

// A click-drag across empty space prefills exactly the block that was drawn. The two ends may arrive in any
// order, and a drag too short to be a real block falls back to the one-hour default so the form never opens
// on a zero-length visit.
export function draftFromRange(day: string, aMinutes: number, bMinutes: number): NewVisitDraft {
	const lo = snapMinutes(Math.min(aMinutes, bMinutes));
	const hi = snapMinutes(Math.max(aMinutes, bMinutes));
	if (hi - lo < MIN_VISIT_MINUTES) return draftFromClick(day, lo);
	return {
		visit_date: day,
		start_time: formatClock(lo),
		end_time: formatClock(hi),
		all_day: false
	};
}

// A click in the Anytime lane, or on a month cell, starts a date-only visit: it belongs to the day but has
// no clock time. This is what Jobber's month click and Anytime cell both create.
export function draftAnytime(day: string): NewVisitDraft {
	return { visit_date: day, start_time: null, end_time: null, all_day: true };
}

/** The visit's current schedule, in proposal shape, for showing "was" beside "will be". */
export function toProposal(visit: VisitSchedule): ScheduleProposal {
	const start = clockMinutes(visit.start_time);
	const end = clockMinutes(visit.end_time);
	return {
		visit_date: visit.visit_date,
		start_time: start === null ? null : formatClock(start),
		end_time: end === null ? null : formatClock(end),
		all_day: visit.all_day,
		assignee_ids: visit.assignee_ids
	};
}

/** Whether a save means this visit alone or carries onto the job's later visits. */
export type MoveScope = 'single' | 'future';

export type ScheduleChange = {
	date: boolean;
	/** The clock start moved, the duration stayed. */
	time: boolean;
	duration: boolean;
	assignment: boolean;
	/** Timed work became Anytime, or the other way round. */
	shape: 'to_anytime' | 'to_timed' | null;
	/** False when the drag put everything back where it started. */
	changed: boolean;
};

export function describeChange(visit: VisitSchedule, proposal: ScheduleProposal): ScheduleChange {
	const before = toProposal(visit);
	const wasTimed = before.start_time !== null;
	const isTimed = proposal.start_time !== null;

	const date = before.visit_date !== proposal.visit_date;
	const time = wasTimed && isTimed && before.start_time !== proposal.start_time;
	const duration =
		wasTimed && isTimed && durationOf(before) !== durationOf(proposal) && before.end_time !== null;
	const assignment = !sameIds(before.assignee_ids, proposal.assignee_ids);
	const shape = wasTimed === isTimed ? null : isTimed ? 'to_timed' : 'to_anytime';

	return {
		date,
		time,
		duration,
		assignment,
		shape,
		changed: date || time || duration || assignment || shape !== null
	};
}

function durationOf(proposal: ScheduleProposal): number | null {
	const start = clockMinutes(proposal.start_time);
	const end = clockMinutes(proposal.end_time);
	if (start === null || end === null) return null;
	return end - start;
}

function sameIds(a: string[], b: string[]): boolean {
	if (a.length !== b.length) return false;
	const left = [...a].sort();
	const right = [...b].sort();
	return left.every((id, index) => id === right[index]);
}

// What "this and future visits" would actually carry forward. The Jobs command copies a visit's time of day
// and its crew and nothing else, so a change it cannot carry -- a new date, or dropping the clock time -- is
// this-visit-only whatever the person picks. The approved contract says the same thing in words: moving a
// visit to another date changes that visit alone.
export function futureScopeFields(change: ScheduleChange): {
	time_of_day: boolean;
	assigned_team: boolean;
} {
	return {
		time_of_day: change.shape === null && (change.time || change.duration),
		assigned_team: change.assignment
	};
}

/** Whether offering "this and future visits" would do anything at all. */
export function canApplyToFuture(change: ScheduleChange): boolean {
	const fields = futureScopeFields(change);
	return fields.time_of_day || fields.assigned_team;
}

/** A completed visit is never dragged, and neither is one the reader may not schedule. */
export function canDragVisit(
	visit: { completed_at: string | null },
	canSchedule: boolean
): boolean {
	return canSchedule && visit.completed_at === null;
}

/** The day a given number of days from another, for keyboard moves. */
export function shiftDay(day: string, days: number): string {
	return parseDate(day).add({ days }).toString();
}
