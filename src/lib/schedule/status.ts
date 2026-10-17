import type { VisitDerivedStatus, VisitShape } from '$lib/schedule/statuses';

// The one rule for reading a visit. The Schedule asks it, and the Job's Visits card asks it, so the two
// screens cannot describe the same visit differently -- the parity the behaviour contract requires.
//
// Both answers come off columns the database already stores. Nothing here invents a state, and neither
// answer is ever written back.

export type VisitTiming = {
	visit_date: string | null;
	start_time: string | null;
	completed_at: string | null;
};

// The database comment on job_visits is the authority: no date is the backlog, a date with no start_time is
// the anytime shape, a date with a start_time is a booked appointment. `all_day` is not consulted, because
// its own constraint already forces start_time to be null whenever it is true.
export function visitShape(visit: Pick<VisitTiming, 'visit_date' | 'start_time'>): VisitShape {
	if (visit.visit_date === null) return 'unscheduled';
	return visit.start_time === null ? 'anytime' : 'scheduled';
}

// `today` is the contractor's own calendar day as YYYY-MM-DD, worked out in the organization's timezone by
// the caller. Dates are compared as plain strings, which is exactly what that format is for, and no visit
// date is ever put through a UTC conversion that could move it a day.
//
// The day is the unit, matching how a job's own status is derived in the database: a visit booked for two
// o'clock is still Today at three, not Late. Late begins when its day has passed. An unscheduled visit sits
// in the backlog and has no status at all until somebody gives it a date.
export function visitDerivedStatus(visit: VisitTiming, today: string): VisitDerivedStatus | null {
	if (visit.completed_at !== null) return 'completed';
	if (visit.visit_date === null) return null;
	if (visit.visit_date < today) return 'late';
	if (visit.visit_date === today) return 'today';
	return 'upcoming';
}

// What a calendar card wears. The Schedule's card colour says where the work stands, in one reading order:
// done, then late, then nobody assigned, then happening right now, and otherwise plain. These are all read off
// columns the visit already has -- no new state is stored -- so the card, the legend and the day heading all
// agree. "Happening now" is only ever true for today, between the visit's own start and end time.
export type CardState = 'completed' | 'late' | 'unassigned' | 'in-progress' | 'scheduled';

export type CardStateInput = VisitTiming & {
	end_time: string | null;
	assignee_ids: string[];
};

function minutesOf(clock: string | null): number | null {
	if (!clock) return null;
	const [hour, minute] = clock.split(':').map(Number);
	return Number.isFinite(hour) ? hour * 60 + (Number.isFinite(minute) ? minute : 0) : null;
}

export function cardState(
	item: CardStateInput,
	today: string,
	nowMinutes: number | null
): CardState {
	if (item.completed_at !== null) return 'completed';
	if (item.visit_date !== null && item.visit_date < today) return 'late';
	if (item.assignee_ids.length === 0) return 'unassigned';
	if (item.visit_date === today && nowMinutes !== null) {
		const start = minutesOf(item.start_time);
		const end = minutesOf(item.end_time);
		if (start !== null && end !== null && start <= nowMinutes && nowMinutes < end) {
			return 'in-progress';
		}
	}
	return 'scheduled';
}

export const CARD_STATE_LABELS: Record<Exclude<CardState, 'scheduled' | 'completed'>, string> = {
	late: 'Late',
	unassigned: 'Unassigned',
	'in-progress': 'In progress'
};
