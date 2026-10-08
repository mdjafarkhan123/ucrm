import { z } from 'zod';
import { MAX_DAYS_BEFORE, MAX_MINUTES_BEFORE, MAX_REMINDERS } from '$lib/jafar/calendar';
import { calendarDate } from './owner.schema';

// Jafar business management C2: what the calendar's routes accept. The database checks the same rules again; these
// give each field its own message first.

const channel = z.enum(['in_app', 'email'], { error: 'Choose an alert or an email.' });

export const timedReminderSchema = z.strictObject({
	channel,
	minutes_before: z
		.number()
		.int()
		.min(0)
		.max(MAX_MINUTES_BEFORE, 'A reminder comes at most 4 weeks before.')
});

export const dayReminderSchema = z.strictObject({
	channel,
	days_before: z
		.number()
		.int()
		.min(0)
		.max(MAX_DAYS_BEFORE, 'A reminder comes at most 28 days before.'),
	at: z.string().regex(/^([01][0-9]|2[0-3]):[0-5][0-9]$/, 'Choose a time of day.')
});

const tooMany = `Choose up to ${MAX_REMINDERS} reminders.`;
export const timedRemindersSchema = z.array(timedReminderSchema).max(MAX_REMINDERS, tooMany);
export const dayRemindersSchema = z.array(dayReminderSchema).max(MAX_REMINDERS, tooMany);

/** An IANA time zone the browser can use ("Asia/Dhaka"); the database checks it is one it knows. */
export const timeZoneSchema = z
	.string()
	.min(1)
	.max(64)
	.refine((zone) => {
		try {
			new Intl.DateTimeFormat('en', { timeZone: zone });
			return true;
		} catch {
			return false;
		}
	}, 'That time zone is not known.');

const instant = z.iso.datetime({ offset: true, error: 'Choose a valid time.' });
const optionalText = (max: number, message: string) =>
	z
		.string()
		.trim()
		.max(max, message)
		.nullish()
		.transform((value) => value || null);

const DAY_MS = 24 * 60 * 60 * 1000;

function checkSpan(value: { starts_at: string; ends_at: string }, context: z.RefinementCtx) {
	const span = Date.parse(value.ends_at) - Date.parse(value.starts_at);
	if (span <= 0)
		context.addIssue({ code: 'custom', path: ['ends_at'], message: 'End after it starts.' });
	else if (span > DAY_MS)
		context.addIssue({ code: 'custom', path: ['ends_at'], message: 'Keep it within one day.' });
}

const span = { starts_at: instant, ends_at: instant };

export const calendarEntryCreateSchema = z.discriminatedUnion('kind', [
	z
		.strictObject({
			kind: z.literal('call'),
			relationship_id: z.uuid('Choose the business.'),
			...span,
			title: optionalText(200, 'Keep the title under 200 characters.'),
			notes: optionalText(4000, 'Keep the notes under 4,000 characters.'),
			reminders: timedRemindersSchema.nullable().default(null),
			/** The browser's time zone, saved as Jafar's when he has none yet. */
			time_zone: timeZoneSchema.optional()
		})
		.superRefine(checkSpan),
	z
		.strictObject({
			kind: z.literal('busy'),
			...span,
			title: optionalText(200, 'Keep the label under 200 characters.'),
			time_zone: timeZoneSchema.optional()
		})
		.superRefine(checkSpan)
]);

export const calendarEntryChangeSchema = z.discriminatedUnion('action', [
	z.strictObject({ action: z.literal('move'), ...span }).superRefine(checkSpan),
	z.strictObject({
		action: z.literal('edit'),
		title: optionalText(200, 'Keep the title under 200 characters.'),
		notes: optionalText(4000, 'Keep the notes under 4,000 characters.'),
		reminders: timedRemindersSchema.nullable()
	}),
	z
		.strictObject({
			action: z.literal('busy'),
			...span,
			title: optionalText(200, 'Keep the label under 200 characters.')
		})
		.superRefine(checkSpan),
	z.strictObject({
		action: z.literal('close'),
		outcome: z.enum(['held', 'no_show', 'cancelled']),
		next_action: z
			.strictObject({
				text: z.string().trim().min(1, 'Say what the next action is.').max(200),
				due_on: calendarDate,
				due_at: instant.nullable().default(null)
			})
			.nullable()
			.default(null)
	})
]);

export const calendarWindowQuerySchema = z
	.object({ from: calendarDate, to: calendarDate, zone: timeZoneSchema })
	.refine((value) => value.to >= value.from, { path: ['to'], message: 'The end comes first.' });

export const calendarPreferencesSchema = z
	.strictObject({
		time_zone: timeZoneSchema.optional(),
		reminder_defaults: z
			.strictObject({
				call: timedRemindersSchema.optional(),
				follow_up_day: dayRemindersSchema.optional(),
				follow_up_timed: timedRemindersSchema.optional()
			})
			.optional()
	})
	.refine((value) => value.time_zone || value.reminder_defaults, {
		path: ['form'],
		message: 'Nothing to change.'
	});

export type CalendarEntryCreateInput = z.infer<typeof calendarEntryCreateSchema>;
export type CalendarEntryChangeInput = z.infer<typeof calendarEntryChangeSchema>;
