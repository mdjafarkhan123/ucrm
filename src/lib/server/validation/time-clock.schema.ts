import { z } from 'zod';

// Time clock (docs/time-clock-behavior-contract.md). Whose timer it is never travels from the browser: the
// commands time the signed-in person, so there is nothing here to name someone else with.

export const startVisitTimerSchema = z.object({
	job_id: z.string().uuid('Choose the job to time.'),
	visit_id: z.string().uuid('Choose the visit to time.')
});

export type StartVisitTimerInput = z.infer<typeof startVisitTimerSchema>;

// Stop, Clock in and Clock out carry nothing — they always mean "my own timer" — but an unexpected body is
// refused rather than ignored, so a caller that thinks it can name a timer or a person finds out.
export const emptyTimerCommandSchema = z.object({}).strict();

// Timesheets (plan § Timesheets page). The page names a day and whether it wants that day or its week; the
// database turns that into the business's own dates, and a missing day means today there.
export const TIMESHEET_SPANS = ['day', 'week'] as const;
export type TimesheetSpan = (typeof TIMESHEET_SPANS)[number];

export const timesheetSummaryQuerySchema = z.object({
	span: z.enum(TIMESHEET_SPANS, { error: 'Choose Day or Week.' }).default('week'),
	date: z.iso.date({ error: 'Pick a valid day.' }).optional()
});

const DAY_MS = 24 * 60 * 60 * 1000;

// One person's entries for the window the summary answered with: a day, or at most a week.
export const timesheetEntriesQuerySchema = z
	.object({
		user_id: z.string().uuid('Choose whose hours to show.'),
		from: z.iso.date({ error: 'Pick a valid start day.' }),
		to: z.iso.date({ error: 'Pick a valid end day.' })
	})
	.refine((query) => query.from <= query.to, {
		message: 'The end day must not be before the start day.',
		path: ['to']
	})
	.refine((query) => Date.parse(query.to) - Date.parse(query.from) <= 6 * DAY_MS, {
		message: 'Choose a day or a week.',
		path: ['to']
	});
