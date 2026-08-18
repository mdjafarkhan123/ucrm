import type { StatusTone } from '$lib/components/work/types';

// The request statuses, in one place both the server and the browser can read. The server adds the rule
// for working the calendar ones out; this file only says which statuses exist and what they are called.
export const STORED_REQUEST_STATUSES = [
	'new',
	'unscheduled',
	'assessment_completed',
	'completed',
	'converted',
	'archived'
] as const;

export const REQUEST_SCHEDULE_STATES = ['today', 'upcoming', 'overdue'] as const;

// Every status the office can actually see on a request, stored and calendar ones together.
export const DISPLAY_REQUEST_STATUSES = [
	...STORED_REQUEST_STATUSES,
	...REQUEST_SCHEDULE_STATES
] as const;

export type StoredRequestStatus = (typeof STORED_REQUEST_STATUSES)[number];
export type RequestScheduleState = (typeof REQUEST_SCHEDULE_STATES)[number];
export type DisplayRequestStatus = StoredRequestStatus | RequestScheduleState;

export const REQUEST_STATUS_LABELS: Record<DisplayRequestStatus, string> = {
	new: 'New',
	unscheduled: 'Unscheduled',
	today: 'Today',
	upcoming: 'Upcoming',
	overdue: 'Overdue',
	assessment_completed: 'Assessment complete',
	completed: 'Completed',
	converted: 'Converted',
	archived: 'Archived'
};

// Requests have nine statuses; the design system has five tones. This is where one becomes the other,
// and it belongs to requests rather than to any shared component — a quote or an invoice maps its own.
export const REQUEST_STATUS_TONES: Record<DisplayRequestStatus, StatusTone> = {
	new: 'informative',
	unscheduled: 'inactive',
	today: 'warning',
	upcoming: 'informative',
	overdue: 'critical',
	assessment_completed: 'success',
	completed: 'success',
	converted: 'success',
	archived: 'inactive'
};
