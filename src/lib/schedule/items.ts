import type { ScheduleAssessment, ScheduleEvent, ScheduleVisit } from '$lib/schedule/api';
import { calendarDay, clockMinutesInZone } from '$lib/time/calendar-day';

// The calendar draws more than visits from Version 1.1 on: it also shows Request-owned assessments and
// Schedule-owned events. They are different business objects with different owners, so the calendar unifies
// their *presentation*, not their identity -- a `kind` tag says which one a card is, and everything that only
// cares about geometry (which day, which hour, how long, who is on it, whether it is done) reads the same
// fields off any of them. That shared shape is what the layout, row and grouping maths operate on, so one
// column packer places a visit, an assessment and an event side by side instead of drawing them on top of
// each other.

/** A job visit on the calendar. */
export type VisitItem = ScheduleVisit & { kind: 'visit' };

/** A Request-owned on-site assessment on the calendar. The calendar shows it and opens its Request; it never
 * edits the assessment's own truth, which stays on the Request surface. Its day and clock time are already in
 * the organization timezone here -- the raw instants were converted once, when the window arrived. */
export type AssessmentItem = {
	kind: 'assessment';
	id: string;
	request_id: string;
	/** Org-timezone day, or null if somehow undated (a window item always has one). */
	visit_date: string | null;
	/** Org-timezone clock time, or null for an Anytime assessment -- the same shape a visit's Anytime uses. */
	start_time: string | null;
	end_time: string | null;
	all_day: boolean;
	completed_at: string | null;
	assignee_ids: string[];
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
};

/** A Schedule-owned event on the calendar (Version 1.1) -- a whole-team block with no client and no owner
 * outside Schedule. It exposes the same geometry fields as the other items so the shared layout, grouping and
 * row maths read it without a special case: it never has a crew (`assignee_ids` is always empty) and never
 * completes (`completed_at` is always null), so it groups as unassigned and is never drawn "done". Its day is
 * already the organization's own -- a plain stored date, no conversion. */
export type EventItem = {
	kind: 'event';
	id: string;
	title: string;
	description: string | null;
	/** The grid's geometry field; this is the event's own `event_date`, always present. */
	visit_date: string | null;
	start_time: string | null;
	end_time: string | null;
	all_day: boolean;
	/** Events have no completion. Always null, so the shared status/grouping code reads it uniformly. */
	completed_at: null;
	/** Events have no individual assignment. Always empty, so the employee filter treats them as whole-team. */
	assignee_ids: string[];
};

export type ScheduleItem = VisitItem | AssessmentItem | EventItem;

// The per-day and per-row totals count every calendar item -- visits, assessments and events alike -- so the
// label stays kind-neutral. Calling a whole-team event or an assessment a "visit" is a small lie, and on the
// Day board's Unassigned pile it reads as unstaffed work that isn't there.
export function itemCountLabel(count: number): string {
	return `${count} ${count === 1 ? 'item' : 'items'}`;
}

export function visitToItem(visit: ScheduleVisit): VisitItem {
	return { ...visit, kind: 'visit' };
}

// Turn a Schedule-owned event row into a calendar item. Its date and clock are already the organization's own
// plain values, so unlike an assessment there is nothing to convert -- it is only tagged and given the empty
// crew and null completion the shared maths expect.
export function eventToItem(event: ScheduleEvent): EventItem {
	return {
		kind: 'event',
		id: event.id,
		title: event.title,
		description: event.description,
		visit_date: event.event_date,
		start_time: event.start_time,
		end_time: event.end_time,
		all_day: event.all_day,
		completed_at: null,
		assignee_ids: []
	};
}

/** An instant, as the wall-clock time of the organization's day it falls in: `14:30`. The calendar reads every
 * time in the contractor's own timezone, so an assessment booked as an instant is converted the same way. */
function orgClock(iso: string, timezone: string): string {
	const minutes = clockMinutesInZone(new Date(iso), timezone);
	const hour = Math.floor(minutes / 60);
	const minute = minutes % 60;
	return `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
}

// Turn a raw-instant assessment from the window read into a calendar item placed in the organization's own day
// and clock. Anytime keeps the day and drops the clock, exactly like an Anytime visit, so it sits in the
// Anytime lane rather than being forced onto the time axis.
export function assessmentToItem(assessment: ScheduleAssessment, timezone: string): AssessmentItem {
	const start = assessment.starts_at ? new Date(assessment.starts_at) : null;
	const timed = start !== null && !assessment.all_day;
	return {
		kind: 'assessment',
		id: assessment.id,
		request_id: assessment.request_id,
		visit_date: start ? calendarDay(start, timezone) : null,
		start_time: timed ? orgClock(assessment.starts_at!, timezone) : null,
		end_time: timed && assessment.ends_at ? orgClock(assessment.ends_at, timezone) : null,
		all_day: assessment.all_day,
		completed_at: assessment.completed_at,
		assignee_ids: assessment.assignee_ids,
		request_title: assessment.request_title,
		request_status: assessment.request_status,
		client_id: assessment.client_id,
		client_name: assessment.client_name,
		client_company_name: assessment.client_company_name,
		property_id: assessment.property_id,
		property_label: assessment.property_label,
		property_address_line1: assessment.property_address_line1,
		property_city: assessment.property_city,
		property_state_region: assessment.property_state_region,
		property_postal_code: assessment.property_postal_code
	};
}
