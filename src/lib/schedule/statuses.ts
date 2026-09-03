import type { StatusTone } from '$lib/components/work/types';

// A visit's status is not stored. It is read off the visit's own date, time and completion stamp against
// the contractor's own calendar day, by the one rule in `$lib/schedule/status.ts`. This file only says what
// each answer is called and which tone it wears, so the Schedule and the Job's Visits card cannot end up
// with two different vocabularies for the same four states.
export const VISIT_DERIVED_STATUSES = ['upcoming', 'today', 'late', 'completed'] as const;

export type VisitDerivedStatus = (typeof VISIT_DERIVED_STATUSES)[number];

export const VISIT_STATUS_LABELS: Record<VisitDerivedStatus, string> = {
	upcoming: 'Upcoming',
	today: 'Today',
	late: 'Late',
	completed: 'Completed'
};

export const VISIT_STATUS_TONES: Record<VisitDerivedStatus, StatusTone> = {
	upcoming: 'informative',
	today: 'success',
	late: 'critical',
	completed: 'inactive'
};

// Where a visit sits, read off its stored date and time exactly as the database comment describes: no date
// is the backlog, a date without a clock time is anytime, a date with one is a booked appointment. This is
// not a status and never mixes with one -- the contract keeps Status and schedule shape apart.
export const VISIT_SHAPES = ['scheduled', 'anytime', 'unscheduled'] as const;

export type VisitShape = (typeof VISIT_SHAPES)[number];

// The three date windows the Schedule can ask for. Part 3 replaces the workspace under them with real
// Week, Day and Month calendars; the window each one means is decided here from now on.
export const SCHEDULE_VIEWS = ['day', 'week', 'month'] as const;

export type ScheduleView = (typeof SCHEDULE_VIEWS)[number];

export const SCHEDULE_VIEW_LABELS: Record<ScheduleView, string> = {
	day: 'Day',
	week: 'Week',
	month: 'Month'
};
