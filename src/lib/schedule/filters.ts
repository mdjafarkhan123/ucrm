import { CalendarDate, parseDate, startOfMonth, startOfWeek } from '@internationalized/date';
import {
	SCHEDULE_VIEWS,
	VISIT_DERIVED_STATUSES,
	type ScheduleView,
	type VisitDerivedStatus
} from '$lib/schedule/statuses';

// The Schedule's whole memory. Everything the control row sets lives in the URL and nowhere else, which is
// what makes refresh, the back button and sharing a link work without a line of code for any of them. The
// Pipeline board is built the same way.

/** Who the calendar is showing: everyone, the unassigned pile, or one employee's id. */
export type ScheduleEmployeeFilter = 'all' | 'unassigned' | string;

export type ScheduleFilters = {
	/** The anchor day, YYYY-MM-DD. The view decides what window grows around it. */
	date: string;
	view: ScheduleView;
	employee: ScheduleEmployeeFilter;
	/** 'all' means every status. */
	status: VisitDerivedStatus | 'all';
};

const ISO_DAY = /^\d{4}-\d{2}-\d{2}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const SUNDAY_START_LOCALE = 'en-US';

// A day string, only if it is a real day. '2026-02-31' passes the shape test and is still not a date, so it
// is parsed rather than trusted.
function readDay(raw: string | null): string | null {
	if (!raw || !ISO_DAY.test(raw)) return null;
	try {
		return parseDate(raw).toString();
	} catch {
		return null;
	}
}

export function readScheduleFilters(
	params: URLSearchParams,
	fallbackDate: string
): ScheduleFilters {
	const view = params.get('view');
	const employee = params.get('employee');
	const status = params.get('status');

	return {
		date: readDay(params.get('date')) ?? fallbackDate,
		view: (SCHEDULE_VIEWS as readonly string[]).includes(view ?? '')
			? (view as ScheduleView)
			: 'week',
		employee: employee === 'unassigned' || (employee && UUID.test(employee)) ? employee : 'all',
		status: (VISIT_DERIVED_STATUSES as readonly string[]).includes(status ?? '')
			? (status as VisitDerivedStatus)
			: 'all'
	};
}

// Only what differs from the default is written, so a plain /schedule link stays plain.
export function scheduleFilterParams(filters: ScheduleFilters, defaultDate: string) {
	const params = new URLSearchParams();
	if (filters.date !== defaultDate) params.set('date', filters.date);
	if (filters.view !== 'week') params.set('view', filters.view);
	if (filters.employee !== 'all') params.set('employee', filters.employee);
	if (filters.status !== 'all') params.set('status', filters.status);
	return params;
}

export type ScheduleWindow = { from: string; to: string };

// What each view actually asks the database for. Day is one day, Week is that day's Sunday to Saturday, and
// Month is the padded month the grid draws: the Sunday on or before the 1st, plus 41 days. That is six full
// weeks, so the cells either side of the month show their real work instead of sitting empty, and it is
// exactly the 42 days the window route already allows.
export function scheduleWindow(date: string, view: ScheduleView): ScheduleWindow {
	const day = parseDate(date);
	if (view === 'day') return { from: day.toString(), to: day.toString() };
	if (view === 'month') {
		const first = startOfWeek(startOfMonth(day), SUNDAY_START_LOCALE);
		return { from: first.toString(), to: first.add({ days: 41 }).toString() };
	}
	const first = startOfWeek(day, SUNDAY_START_LOCALE);
	return { from: first.toString(), to: first.add({ days: 6 }).toString() };
}

// Previous and next move by exactly the window the person is looking at.
export function shiftScheduleDate(date: string, view: ScheduleView, direction: -1 | 1) {
	const day = parseDate(date);
	if (view === 'day') return day.add({ days: direction }).toString();
	if (view === 'week') return day.add({ weeks: direction }).toString();
	// A month step keeps the day of the month where it can: CalendarDate clamps 31 January + 1 month to
	// the last day of February rather than spilling into March.
	return day.add({ months: direction }).toString();
}

// Changing view keeps the closest equivalent date, as the contract requires. Week and Day already point at
// a real day; only a month anchor needs to land somewhere sensible, and the first of the month is that.
export function reanchorScheduleDate(date: string, from: ScheduleView, to: ScheduleView) {
	if (from !== 'month' || to === 'month') return date;
	return startOfMonth(parseDate(date)).toString();
}

export function eachDayInWindow(window: ScheduleWindow): string[] {
	const days: string[] = [];
	let cursor: CalendarDate = parseDate(window.from);
	const last = parseDate(window.to);
	while (cursor.compare(last) <= 0) {
		days.push(cursor.toString());
		cursor = cursor.add({ days: 1 });
	}
	return days;
}
