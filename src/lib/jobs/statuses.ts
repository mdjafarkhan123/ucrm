import type { StatusTone } from '$lib/components/work/types';

// A job's status is never stored. `private.job_derived_status` and `private.job_status_with_visits` in the
// database work it out from the stored state, the job's visits and the clock, and this file only says what each answer is called and which
// tone it wears. The database is the source; nothing here re-derives anything.
export const JOB_DERIVED_STATUSES = [
	'upcoming',
	'today',
	'late',
	'unscheduled',
	'action_required',
	'requires_invoicing',
	'ending_soon',
	'archived'
] as const;

export type JobDerivedStatus = (typeof JOB_DERIVED_STATUSES)[number];

export const JOB_STATUS_LABELS: Record<JobDerivedStatus, string> = {
	upcoming: 'Upcoming',
	today: 'Today',
	late: 'Late',
	unscheduled: 'Unscheduled',
	action_required: 'Action required',
	requires_invoicing: 'Requires invoicing',
	ending_soon: 'Ending soon',
	archived: 'Archived'
};

export const JOB_STATUS_TONES: Record<JobDerivedStatus, StatusTone> = {
	upcoming: 'informative',
	today: 'success',
	late: 'critical',
	unscheduled: 'warning',
	action_required: 'warning',
	requires_invoicing: 'warning',
	ending_soon: 'warning',
	archived: 'inactive'
};

// The five the office acts on, in the order Jobber's own Overview lists them.
export const JOB_OVERVIEW_STATUSES = [
	'ending_soon',
	'late',
	'requires_invoicing',
	'action_required',
	'unscheduled'
] as const;

// Every status the database can answer with, in the order the office reads them: what is coming up first,
// then what needs a hand.
export const JOB_FILTERABLE_STATUSES = [
	'today',
	'upcoming',
	'late',
	'unscheduled',
	'action_required',
	'requires_invoicing',
	'ending_soon',
	'archived'
] as const;

export const JOB_TYPES = ['one_off', 'recurring'] as const;

export type JobType = (typeof JOB_TYPES)[number];

export const JOB_TYPE_LABELS: Record<JobType, string> = {
	one_off: 'One-off',
	recurring: 'Recurring'
};
