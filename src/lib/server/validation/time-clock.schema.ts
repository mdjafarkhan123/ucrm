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

// Corrections (plan § Timesheets page). Times are the business's own clock, as the page shows them: a day,
// and hours and minutes. The database turns them into instants in the business's time zone, so a phone set to
// another zone records the same hours. An end at or before the start is the next morning.
const clockTime = z
	.string({ error: 'Pick a time.' })
	.regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Pick a time.');

const entryNotes = z
	.string()
	.trim()
	.max(2000, 'Keep the note under 2000 characters.')
	.nullish()
	.transform((notes) => notes || null);

// What an entry is for, and when. No job means General time, which has no visit.
export const timesheetEntrySchema = z
	.object({
		user_id: z.string().uuid('Choose whose hours these are.'),
		job_id: z.string().uuid('Choose a job.').nullable(),
		visit_id: z.string().uuid('That visit could not be found.').nullable().default(null),
		day: z.iso.date({ error: 'Pick the day.' }),
		start_time: clockTime,
		end_time: clockTime,
		notes: entryNotes
	})
	.strict()
	.refine((entry) => entry.job_id !== null || entry.visit_id === null, {
		message: 'General time has no visit.',
		path: ['visit_id']
	})
	.refine((entry) => entry.start_time !== entry.end_time, {
		message: 'The end time must be different from the start time.',
		path: ['end_time']
	});

export type TimesheetEntryInput = z.infer<typeof timesheetEntrySchema>;

// While a timer runs only its start and notes can change.
export const runningTimerChangeSchema = z
	.object({
		day: z.iso.date({ error: 'Pick the day the timer started.' }),
		start_time: clockTime,
		notes: entryNotes
	})
	.strict();

export type RunningTimerChangeInput = z.infer<typeof runningTimerChangeSchema>;

// Clock out or stop: now when nothing is sent, otherwise the day and time work really ended.
export const stopTimerAtSchema = z
	.object({
		day: z.iso.date({ error: 'Pick the day work ended.' }).optional(),
		time: clockTime.optional()
	})
	.strict()
	.refine((stop) => (stop.day === undefined) === (stop.time === undefined), {
		message: 'Choose both the day and the time work ended.',
		path: ['time']
	});

export type StopTimerAtInput = z.infer<typeof stopTimerAtSchema>;

// Weekly approval (plan § Weekly approval): every stopped entry up to and including a day, for the chosen
// people. The database refuses a day after the business's today.
export const timesheetApprovalQuerySchema = z.object({
	date: z.iso.date({ error: 'Pick the day to approve up to.' })
});

export const approveTimesheetsSchema = z
	.object({
		cutoff: z.iso.date({ error: 'Pick the day to approve up to.' }),
		user_ids: z
			.array(z.string().uuid('That person could not be found.'))
			.min(1, 'Choose at least one person.')
			.max(500, 'Choose fewer people.')
			.transform((ids) => [...new Set(ids)])
	})
	.strict();

export type ApproveTimesheetsInput = z.infer<typeof approveTimesheetsSchema>;
