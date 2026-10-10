import { z } from 'zod';
import {
	BUFFER_CHOICES,
	CHANGE_DEADLINE_CHOICES,
	DURATION_CHOICES,
	HORIZON_CHOICES,
	INTERVAL_CHOICES,
	MAX_RANGES_PER_DAY,
	MAX_VISITOR_REMINDERS,
	NOTICE_CHOICES,
	VISITOR_REMINDER_CHOICES
} from '$lib/jafar/booking';
import { timeZoneSchema } from './calendar.schema';

// Jafar business management E1/E3: what the booking routes accept. The database checks the same rules again; these
// give each field its own message first.

const clock = z.string().regex(/^([01][0-9]|2[0-3]):[0-5][0-9]$/, 'Choose a time.');
const oneOf = <T extends readonly number[]>(choices: T, message: string) =>
	z.number().refine((value) => (choices as readonly number[]).includes(value), message);

export const bookingHoursSchema = z
	.array(
		z
			.strictObject({ weekday: z.number().int().min(0).max(6), start: clock, end: clock })
			.refine((range) => range.end > range.start, {
				message: 'End after it starts.',
				path: ['end']
			})
	)
	.max(28)
	.superRefine((hours, context) => {
		hours.forEach((range, index) => {
			const sameDay = hours.filter((other) => other.weekday === range.weekday);
			if (sameDay.length > MAX_RANGES_PER_DAY)
				context.addIssue({
					code: 'custom',
					path: [index, 'start'],
					message: `Keep to ${MAX_RANGES_PER_DAY} ranges a day.`
				});
			const overlaps = hours.some(
				(other, otherIndex) =>
					otherIndex !== index &&
					other.weekday === range.weekday &&
					other.start < range.end &&
					range.start < other.end
			);
			if (overlaps)
				context.addIssue({
					code: 'custom',
					path: [index, 'start'],
					message: 'This overlaps another range on the same day.'
				});
		});
	});

/** E3: the public link on or off. */
export const bookingEnabledSchema = z.strictObject({
	enabled: z.boolean(),
	time_zone: timeZoneSchema.optional()
});

const hostId = z.uuid().nullable();

/** E3: one meeting type, added or saved; its default host is one of its hosts. */
export const meetingTypeSchema = z
	.strictObject({
		slug: z
			.string()
			.trim()
			.min(1, 'Give the link an ending.')
			.max(60, 'Keep the link ending under 60 characters.')
			.regex(
				/^[a-z0-9]+(-[a-z0-9]+)*$/,
				'Use lowercase letters, numbers and single dashes, like discovery-call.'
			),
		name: z.string().trim().min(1, 'Give the meeting a name.').max(120, 'Keep the name short.'),
		description: z
			.string()
			.trim()
			.max(1000, 'Keep the description under 1,000 characters.')
			.nullish()
			.transform((value) => value || null),
		duration_minutes: oneOf(DURATION_CHOICES, 'Choose a length.'),
		location_kind: z.enum(['phone', 'zoom', 'google_meet'], 'Choose how the call happens.'),
		video_link_mode: z.enum(['automatic', 'custom'], 'Choose how the link is made.'),
		min_notice_minutes: oneOf(NOTICE_CHOICES, 'Choose the notice.'),
		horizon_days: oneOf(HORIZON_CHOICES, 'Choose how far ahead.'),
		buffer_minutes: oneOf(BUFFER_CHOICES, 'Choose a gap.'),
		slot_interval_minutes: oneOf(INTERVAL_CHOICES, 'Choose how often a time can start.'),
		requires_approval: z.boolean(),
		change_deadline_minutes: oneOf(CHANGE_DEADLINE_CHOICES, 'Choose when changes stop.'),
		is_active: z.boolean(),
		visitor_reminder_minutes: z
			.array(oneOf(VISITOR_REMINDER_CHOICES, 'Choose when the reminder goes.'))
			.max(MAX_VISITOR_REMINDERS, `Keep to ${MAX_VISITOR_REMINDERS} reminders.`)
			.transform((minutes) => [...new Set(minutes)].sort((a, b) => b - a)),
		host_member_id: hostId,
		host_member_ids: z
			.array(hostId)
			.min(1, 'Choose at least one host.')
			.max(50)
			.transform((ids) => [...new Set(ids)])
	})
	.refine((type) => type.host_member_ids.includes(type.host_member_id), {
		message: 'The default host must be one of the hosts.',
		path: ['host_member_id']
	});

export type MeetingTypeBody = z.infer<typeof meetingTypeSchema>;

/** E3: one person's weekly hours. */
export const bookingHoursBodySchema = z.strictObject({
	hours: bookingHoursSchema,
	time_zone: timeZoneSchema.optional()
});

/** E4a: the joining link the host adds to a booked video call. */
export const videoLinkSchema = z.strictObject({
	url: z
		.string()
		.trim()
		.min(1, 'Paste the joining link.')
		.max(2048, 'This link is too long.')
		.refine((value) => {
			try {
				const url = new URL(value);
				return url.protocol === 'https:' && url.hostname.includes('.') && !/\s/.test(value);
			} catch {
				return false;
			}
		}, 'Paste the full link, starting with https://.')
});

/** E3: hand a booked call to another eligible host (null is Jafar). */
export const bookingHostChangeSchema = z.strictObject({ member_id: hostId });

/** The public page's request for open times: a span of at most 45 days. */
export const bookingSlotsQuerySchema = z
	.object({
		from: z.iso.datetime({ offset: true }),
		to: z.iso.datetime({ offset: true })
	})
	.refine((range) => {
		const span = Date.parse(range.to) - Date.parse(range.from);
		return span > 0 && span <= 45 * 24 * 60 * 60 * 1000;
	}, 'Ask for at most 45 days at a time.');

export const publicBookingSchema = z.strictObject({
	starts_at: z.iso.datetime({ offset: true, error: 'Choose a time.' }),
	name: z
		.string()
		.trim()
		.min(1, 'Enter your name.')
		.max(120, 'Keep your name under 120 characters.'),
	email: z
		.string()
		.trim()
		.toLowerCase()
		.max(254, 'Enter a shorter email address.')
		.pipe(z.email('Enter a valid email address.')),
	phone: z
		.string()
		.trim()
		.min(4, 'Enter the number we should call.')
		.max(40, 'Enter a shorter phone number.')
		.regex(/^[+()\d\s.-]+$/, 'Use digits, spaces and + only.')
		.refine(
			(value) => value.replace(/\D/g, '').length >= 6,
			'Enter the full number, with its country code.'
		),
	business_name: z
		.string()
		.trim()
		.min(1, 'Enter your business name.')
		.max(200, 'Keep the business name under 200 characters.'),
	country_code: z
		.string()
		.trim()
		.toUpperCase()
		.regex(/^[A-Z]{2}$/, 'Choose your country.'),
	trade: z.string().trim().min(1, 'Tell us your trade.').max(120, 'Keep your trade short.'),
	note: z
		.string()
		.trim()
		.max(2000, 'Keep this under 2,000 characters.')
		.nullish()
		.transform((value) => value || null),
	time_zone: timeZoneSchema,
	turnstile_token: z.string().max(4096).default('')
});

export type PublicBookingInput = z.infer<typeof publicBookingSchema>;

/** E2: what a visitor does with their link -- move to another open time, or cancel with an optional reason. */
export const bookingChangeSchema = z.discriminatedUnion('action', [
	z.strictObject({
		action: z.literal('move'),
		starts_at: z.iso.datetime({ offset: true, error: 'Choose a time.' })
	}),
	z.strictObject({
		action: z.literal('cancel'),
		reason: z
			.string()
			.trim()
			.max(500, 'Keep this under 500 characters.')
			.nullish()
			.transform((value) => value || null)
	})
]);

/** E2: Jafar's answer to a request -- approve (at the asked time, or another open one) or decline. */
export const bookingDecisionSchema = z.discriminatedUnion('decision', [
	z.strictObject({
		decision: z.literal('approve'),
		starts_at: z.iso.datetime({ offset: true, error: 'Choose a time.' }).nullish()
	}),
	z.strictObject({ decision: z.literal('decline') })
]);
