import type { ScheduleWindow } from '$lib/schedule/filters';

// What the Schedule asks the server for, and the keys TanStack Query holds it under. Two questions, because
// they change at completely different rates: the calendar's operating facts almost never change, and the
// window changes every time somebody clicks Next.

async function readOrThrow<T>(response: Response, fallback: string): Promise<T> {
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw new Error(result.error ?? fallback);
	}
	return response.json();
}

/** One weekday's opening period. Several rows can share a weekday when a business closes for lunch. */
export type BusinessHourPeriod = {
	/** 0 is Sunday, matching the Business Hours screen. */
	weekday: number;
	period_index: number;
	is_open: boolean;
	is_open_24h: boolean;
	opens_at: string | null;
	closes_at: string | null;
};

export type ScheduleContext = {
	/** The organization's timezone. Every day the calendar names is worked out in it. */
	timezone: string;
	/** Only `weekly` means there is a confirmed pattern to shade. */
	hours_mode: 'not_configured' | 'weekly' | 'appointment_only';
	hours: BusinessHourPeriod[];
	/** Whether this person may change the schedule at all: drag, resize and reassign existing visits. */
	can_schedule: boolean;
	/** Whether this person may start a Job from empty calendar space -- the Job-create authority. */
	can_create_job: boolean;
};

export const scheduleContextKey = ['schedule', 'context'] as const;

export async function fetchScheduleContext(): Promise<ScheduleContext> {
	const response = await fetch('/api/schedule/context');
	return readOrThrow<ScheduleContext>(response, 'The calendar settings could not be loaded.');
}

export type ScheduleVisit = {
	id: string;
	job_id: string;
	/** Null never appears in a window read; the backlog is Part 3's drawer. */
	visit_date: string | null;
	start_time: string | null;
	end_time: string | null;
	all_day: boolean;
	/** The visit's own title, when it has one. Otherwise the job's title names it. */
	title: string | null;
	completed_at: string | null;
	revision: number;
	position: number;
	assignee_ids: string[];
	job_number: number | null;
	job_title: string | null;
	client_id: string | null;
	/** Null for a reader without customers.view, not "no client". */
	client_name: string | null;
	client_company_name: string | null;
	property_id: string | null;
	property_label: string | null;
	property_address_line1: string | null;
	property_city: string | null;
	property_state_region: string | null;
	property_postal_code: string | null;
};

export type ScheduleWindowPage = {
	from: string;
	to: string;
	visits: ScheduleVisit[];
	/** The window holds more visits than one read returns. */
	truncated: boolean;
	limit: number;
};

// The backlog: visits with no date, waiting to be placed. It carries everything a window visit does, plus
// the day it was created, so the drawer can say how long a piece of work has been waiting.
export type UnscheduledVisit = ScheduleVisit & {
	/** When the visit was created, for the "waiting N days" age the drawer shows. */
	created_at: string;
};

export type ScheduleUnscheduledPage = {
	visits: UnscheduledVisit[];
	/** The backlog holds more visits than one read returns. */
	truncated: boolean;
	limit: number;
};

// The backlog has no date to key it by. It changes only when a visit is scheduled, unscheduled or created,
// so it is one entry the drawer re-uses until a write invalidates it.
export const scheduleUnscheduledKey = ['schedule', 'unscheduled'] as const;

export async function fetchScheduleUnscheduled(): Promise<ScheduleUnscheduledPage> {
	const response = await fetch('/api/schedule/unscheduled');
	return readOrThrow<ScheduleUnscheduledPage>(
		response,
		'The unscheduled work could not be loaded.'
	);
}

// Keyed by the window and nothing else. Employee and status are applied to the rows already in hand, so
// changing a filter re-uses this entry instead of asking the server again.
export const scheduleWindowKey = (window: ScheduleWindow) =>
	['schedule', 'window', window.from, window.to] as const;

export async function fetchScheduleWindow(window: ScheduleWindow): Promise<ScheduleWindowPage> {
	const params = new URLSearchParams({ from: window.from, to: window.to });
	const response = await fetch(`/api/schedule/visits?${params.toString()}`);
	return readOrThrow<ScheduleWindowPage>(response, 'The schedule could not be loaded.');
}
