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
	/** Whether this person may mark visits complete or incomplete -- the Jobs-owned completion authority. */
	can_complete: boolean;
	/** Whether this person may finish (close) or reopen a job -- gates the "Finish job" final-visit option. */
	can_close: boolean;
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
	/** The property's stored coordinates, present once geocoding has succeeded (7a-4 worker). Null until then,
	 * so the Map draws no pin and the stop list says the location is not ready rather than guessing one. */
	property_latitude: number | null;
	property_longitude: number | null;
	/** Where geocoding stands for this property: pending | succeeded | failed. Lets the stop list tell "not
	 * ready yet" apart from "this address does not resolve" instead of dropping an unmappable stop. */
	property_geocode_status: string | null;
};

// An on-site assessment placed on the calendar (Version 1.1). It is Request-owned: the calendar shows it and
// opens its Request, but never edits its truth. Times arrive as raw UTC instants -- the calendar converts them
// to the org-timezone day and clock the same way it works out Today -- because an assessment stores an instant,
// not a plain date the way a visit does.
export type ScheduleAssessment = {
	id: string;
	request_id: string;
	/** UTC instant. Null never appears in a window read: an undated assessment is the Request's own backlog. */
	starts_at: string | null;
	ends_at: string | null;
	/** Anytime: the day is promised, the hour is not. */
	all_day: boolean;
	completed_at: string | null;
	instructions: string | null;
	assignee_ids: string[];
	/** The Request's title names the assessment. Null for a reader without requests access. */
	request_title: string | null;
	request_status: string | null;
	client_id: string | null;
	client_name: string | null;
	client_company_name: string | null;
	property_id: string | null;
	property_label: string | null;
	property_address_line1: string | null;
	property_city: string | null;
	property_state_region: string | null;
	property_postal_code: string | null;
	/** The property's stored coordinates and geocode status, the same fields a visit carries, so the Map treats
	 * an assessment stop exactly as it treats a visit stop. */
	property_latitude: number | null;
	property_longitude: number | null;
	property_geocode_status: string | null;
};

// A Schedule-owned Event (Version 1.1): a single-day whole-team block -- a meeting, a training, a holiday.
// Unlike a visit or assessment it belongs to no client and no job; Schedule owns it outright. Its day and
// clock are already the organization's own -- a plain date and time, stored the way a visit is, not an
// instant -- so the calendar places it without any timezone conversion.
export type ScheduleEvent = {
	id: string;
	title: string;
	description: string | null;
	/** Org-timezone day. An Event always has one -- it never sits in the Unscheduled backlog. */
	event_date: string;
	/** HH:MM:SS, or null for an Anytime whole-team block. */
	start_time: string | null;
	end_time: string | null;
	all_day: boolean;
};

export type ScheduleWindowPage = {
	from: string;
	to: string;
	visits: ScheduleVisit[];
	/** The window's on-site assessments, raw instants for the browser to place in the org timezone. */
	assessments: ScheduleAssessment[];
	/** The window's Schedule-owned events, plain org-day rows. */
	events: ScheduleEvent[];
	/** The window holds more work than one read returns. */
	truncated: boolean;
	limit: number;
};

// The create/edit form's payload. An Event is timed (day + start time, end optional) or anytime (day, no
// clock); it always has a day and a title. The server validates this shape again before it writes.
export type ScheduleEventWrite = {
	title: string;
	description: string | null;
	event_date: string;
	start_time: string | null;
	end_time: string | null;
	all_day: boolean;
};

export async function createScheduleEvent(input: ScheduleEventWrite): Promise<ScheduleEvent> {
	const response = await fetch('/api/schedule/events', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	const result = await readOrThrow<{ event: ScheduleEvent }>(
		response,
		'The event could not be created.'
	);
	return result.event;
}

export async function updateScheduleEvent(
	id: string,
	input: ScheduleEventWrite
): Promise<ScheduleEvent> {
	const response = await fetch(`/api/schedule/events/${id}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	const result = await readOrThrow<{ event: ScheduleEvent }>(
		response,
		'The event could not be saved.'
	);
	return result.event;
}

export async function deleteScheduleEvent(id: string): Promise<void> {
	const response = await fetch(`/api/schedule/events/${id}`, { method: 'DELETE' });
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw new Error(result.error ?? 'The event could not be deleted.');
	}
}

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
