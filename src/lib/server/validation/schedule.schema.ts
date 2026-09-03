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
