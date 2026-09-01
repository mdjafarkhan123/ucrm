import type { StatusTone } from '$lib/components/work/types';

// A job's status is never stored. `private.job_derived_status` in the database works it out from the
// stored state, the schedule and the clock, and this file only says what each answer is called and which
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

// Visits, invoice reminders and billing arrive in Parts 9 and 11. Until they do, the database can only
// ever answer with these three, so these are the only ones the Status filter offers: a filter that can
// never match anything is worse than one that is honestly short.
export const JOB_FILTERABLE_STATUSES = ['unscheduled', 'ending_soon', 'archived'] as const;

export const JOB_TYPES = ['one_off', 'recurring'] as const;

export type JobType = (typeof JOB_TYPES)[number];

export const JOB_TYPE_LABELS: Record<JobType, string> = {
	one_off: 'One-off',
	recurring: 'Recurring'
};
