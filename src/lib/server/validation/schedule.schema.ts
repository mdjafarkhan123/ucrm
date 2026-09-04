import { z } from 'zod';

// The route validates the window and nothing else. Which employee and which statuses the person is looking
// at never reach the database: the window is already bounded, so the calendar filters the rows it holds and
// answers a filter change instantly instead of asking again.

// The window is bounded before it reaches the database, so no URL can ask one query for a year of one
// tenant's visits. A month is the widest view the calendar has; 42 days is that month plus the padding
// weeks a Part 3 month grid will need at its edges.
export const SCHEDULE_WINDOW_MAX_DAYS = 42;

// The ceiling on what one window read returns. A contractor with a genuinely busier month than this gets an
// honest "too many to show" rather than a page that quietly drops visits -- and the row is never the thing
// that decides how much work the database does, because the window above already did.
export const SCHEDULE_VISIT_LIMIT = 500;

const ISO_DAY = /^\d{4}-\d{2}-\d{2}$/;

const day = z.string().regex(ISO_DAY, 'Use a YYYY-MM-DD date.');

function daysBetween(from: string, to: string) {
	const start = Date.parse(`${from}T00:00:00Z`);
	const end = Date.parse(`${to}T00:00:00Z`);
	return Math.round((end - start) / 86_400_000) + 1;
}

const HHMM = /^([01]\d|2[0-3]):[0-5]\d$/;

// A Schedule-owned Event as the create/edit form sends it. An Event is a single-day whole-team block that is
// either timed (a day plus a start time, end optional) or anytime (a day, no clock). It always has a day --
// Events never sit in the Unscheduled backlog -- and always a title. No client, assignment or recurrence
// reaches here because the contract gives an Event none of those.
export const scheduleEventWriteSchema = z
	.object({
		title: z.string().trim().min(1, 'Give the event a title.').max(160, 'That title is too long.'),
		description: z
			.string()
			.trim()
			.max(2000, 'That description is too long.')
			.nullish()
			.transform((value) => value || null),
		event_date: day,
		start_time: z
			.string()
			.regex(HHMM, 'Enter a time as HH:MM.')
			.nullish()
			.transform((value) => value || null),
		end_time: z
			.string()
			.regex(HHMM, 'Enter a time as HH:MM.')
			.nullish()
			.transform((value) => value || null),
		all_day: z.boolean().default(false)
	})
	// An Event has exactly two clean shapes -- timed or anytime -- so a real calendar date is required and the
	// clock rules mirror the database's own constraints, checked here so a bad combination is a field message
	// rather than a raw constraint error bounced back from the write.
	.refine((value) => !Number.isNaN(Date.parse(`${value.event_date}T00:00:00Z`)), {
		message: 'Use a real calendar date.',
		path: ['event_date']
	})
	.superRefine((value, context) => {
		if (value.all_day && (value.start_time || value.end_time)) {
			context.addIssue({
				code: z.ZodIssueCode.custom,
				message: 'An anytime event carries no start or end time.',
				path: ['all_day']
			});
		}
		if (!value.all_day && !value.start_time) {
			context.addIssue({
				code: z.ZodIssueCode.custom,
				message: 'Give the event a start time, or tick “Anytime”.',
				path: ['start_time']
			});
		}
		if (value.end_time && !value.start_time) {
			context.addIssue({
				code: z.ZodIssueCode.custom,
				message: 'Set a start time before an end time.',
				path: ['start_time']
			});
		}
		if (value.start_time && value.end_time && value.end_time <= value.start_time) {
			context.addIssue({
				code: z.ZodIssueCode.custom,
				message: 'The end time has to come after the start time.',
				path: ['end_time']
			});
		}
	});

export type ScheduleEventWriteInput = z.infer<typeof scheduleEventWriteSchema>;

// A real calendar day: the shape regex above catches `2026-13-40`, this catches `2026-02-31`.
const realDay = day.refine((value) => !Number.isNaN(Date.parse(`${value}T00:00:00Z`)), {
	message: 'Use a real calendar date.'
});

// The ceiling on stop ids one saved route may hold. A day's route can hold no more stops than a day's window
// read returns, so this mirrors SCHEDULE_VISIT_LIMIT and matches the database's own array-length constraint.
const ROUTE_ORDER_MAX_STOPS = SCHEDULE_VISIT_LIMIT;

// A saved route order as the Map sends it: which employee, which day, and the stop ids (Visits and
// Assessments) in the dispatcher's chosen sequence. The ids are a preference list, not references -- a stop
// that has since gone is dropped when the order is applied -- so nothing here checks that they still exist.
export const scheduleRouteOrderWriteSchema = z.object({
	employee_id: z.string().uuid('Choose a real employee.'),
	route_date: realDay,
	order: z
		.array(z.string().uuid('That is not a real stop.'))
		.max(ROUTE_ORDER_MAX_STOPS, 'That route has too many stops to save.')
});

export type ScheduleRouteOrderWriteInput = z.infer<typeof scheduleRouteOrderWriteSchema>;

// The GET reads one employee's saved order for one day, both off the query string.
export const scheduleRouteOrderQuerySchema = z.object({
	employee: z.string().uuid('Choose a real employee.'),
	date: realDay
});

export const scheduleWindowQuerySchema = z
	.object({
		from: day,
		to: day
	})
	// Both ends are real days and the window runs forwards. `2026-02-31` matches the shape above and is
	// still not a date, so it is parsed rather than trusted.
	.refine(
		(value) =>
			!Number.isNaN(Date.parse(`${value.from}T00:00:00Z`)) &&
			!Number.isNaN(Date.parse(`${value.to}T00:00:00Z`)) &&
			new Date(`${value.from}T00:00:00Z`).toISOString().slice(0, 10) === value.from &&
			new Date(`${value.to}T00:00:00Z`).toISOString().slice(0, 10) === value.to,
		{ message: 'Use a real calendar date.', path: ['from'] }
	)
	.refine((value) => value.from <= value.to, {
		message: 'The window has to end on or after it starts.',
		path: ['to']
	})
	.refine((value) => daysBetween(value.from, value.to) <= SCHEDULE_WINDOW_MAX_DAYS, {
		message: `Ask for at most ${SCHEDULE_WINDOW_MAX_DAYS} days at a time.`,
		path: ['to']
	});
