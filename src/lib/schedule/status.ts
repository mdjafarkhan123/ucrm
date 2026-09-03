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
