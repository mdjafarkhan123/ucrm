import type { ScheduleVisit } from '$lib/schedule/api';
import { visitShape } from '$lib/schedule/status';
import type { TeamMember } from '$lib/team/api';

// What a visit is called on a calendar. Every surface that draws a visit asks here, so the Week grid, the
// Day board, the Month cell and the preview cannot end up describing the same visit three different ways.

/** 9am, not 09:00:00. The stored value is a plain clock time with no timezone in it, so it is read as text
 * rather than put through a Date that would attach one. */
export function clockLabel(value: string | null): string | null {
	if (!value) return null;
	const [rawHour, minute] = value.split(':');
	const hour = Number(rawHour);
	if (!Number.isFinite(hour)) return null;
	const suffix = hour < 12 ? 'am' : 'pm';
	const twelve = hour % 12 === 0 ? 12 : hour % 12;
	return minute === '00' ? `${twelve}${suffix}` : `${twelve}:${minute}${suffix}`;
}

/** The full time a card shows when it has the room: `9am – 11am`, or `Anytime`. */
export function visitTimeLabel(visit: ScheduleVisit): string {
	if (visitShape(visit) === 'anytime') return 'Anytime';
	const start = clockLabel(visit.start_time);
	const end = clockLabel(visit.end_time);
	if (!start) return 'Anytime';
	return end ? `${start} – ${end}` : start;
}

/** Just the start, for a card too small to carry a range. */
export function visitStartLabel(visit: ScheduleVisit): string {
	if (visitShape(visit) === 'anytime') return 'Anytime';
	return clockLabel(visit.start_time) ?? 'Anytime';
}

/** The client names the visit. A reader without customers.view gets no name at all, and the card says so
 * rather than leaving a gap that reads like the visit has no client. */
export function visitClientLabel(visit: ScheduleVisit): string {
	return visit.client_name ?? visit.client_company_name ?? 'Client hidden';
}

/** What the work is: the visit's own title, else the job's, else the job number. */
export function visitWorkLabel(visit: ScheduleVisit): string {
	return visit.title ?? visit.job_title ?? `Job #${visit.job_number ?? ''}`.trim();
}

/** Where it is, short enough for a card. Null when the reader may not see the property. */
export function visitPlaceLabel(visit: ScheduleVisit): string | null {
	const parts = [visit.property_label, visit.property_address_line1, visit.property_city].filter(
		(part): part is string => Boolean(part)
	);
	return parts.length > 0 ? parts.join(' · ') : null;
}

/** The full address, for the preview rather than a card. */
export function visitAddressLabel(visit: ScheduleVisit): string | null {
	const street = [visit.property_label, visit.property_address_line1].filter(Boolean).join(' · ');
	const region = [visit.property_city, visit.property_state_region].filter(Boolean).join(', ');
	const line = [street, region, visit.property_postal_code].filter(Boolean).join(' ');
	return line.length > 0 ? line : null;
}

/** Who is going: one name, a name and a count, or the honest absence of either. */
export function visitAssignmentLabel(
	visit: ScheduleVisit,
	employeesById: Map<string, TeamMember>
): string {
	return assignmentLabel(visit.assignee_ids, employeesById);
}

/** The colour a visit's accent wears. One employee lends theirs; a shared visit gets a neutral accent and a
 * count instead, because no employee owns a visit the whole crew is on. */
export function visitAccentColor(
	visit: ScheduleVisit,
	employeesById: Map<string, TeamMember>
): string | null {
	if (visit.assignee_ids.length !== 1) return null;
	return employeesById.get(visit.assignee_ids[0])?.schedule_color ?? null;
}

// Date-only values are formatted as the plain days they are. Reading them in UTC keeps a date from sliding
// a day backwards for a browser that sits west of the contractor.
export function formatCalendarDay(day: string, options: Intl.DateTimeFormatOptions): string {
	return new Intl.DateTimeFormat('en-US', { ...options, timeZone: 'UTC' }).format(
		new Date(`${day}T00:00:00Z`)
	);
}

/** Who is going, from a bare list of ids -- the same sentence a proposal needs before it is saved. */
export function assignmentLabel(
	assigneeIds: string[],
	employeesById: Map<string, TeamMember>
): string {
	if (assigneeIds.length === 0) return 'Unassigned';
	const [first, ...rest] = assigneeIds;
	const name = employeesById.get(first)?.full_name ?? 'One employee';
	return rest.length > 0 ? `${name} +${rest.length}` : name;
}

/** A whole schedule in one line: `Wed, Sep 2 · 9am – 11am`, `Wed, Sep 2 · Anytime`, or `Not scheduled`. */
export function scheduleLabel(schedule: {
	visit_date: string | null;
	start_time: string | null;
	end_time: string | null;
}): string {
	if (!schedule.visit_date) return 'Not scheduled';
	const day = formatCalendarDay(schedule.visit_date, {
		weekday: 'short',
		month: 'short',
		day: 'numeric'
	});
	const start = clockLabel(schedule.start_time);
	if (!start) return `${day} · Anytime`;
	const end = clockLabel(schedule.end_time);
	return end ? `${day} · ${start} – ${end}` : `${day} · ${start}`;
}
