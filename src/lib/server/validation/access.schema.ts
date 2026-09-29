import { z } from 'zod';

export const organizationIdSchema = z.string().uuid();
export const userIdSchema = z.string().uuid();
export const permissionKeySchema = z
	.string()
	.trim()
	.regex(/^[a-z][a-z0-9_.-]{1,79}$/, 'Use a valid permission key.');

// Ownership is handed over, never assigned, so it is not a role this screen can pick. The database
// refuses it too; refusing it here is what turns a raised exception into a field message.
export const assignableRoleSchema = z.enum(['admin', 'office', 'sales', 'field', 'finance']);

const invitationPermissionAdjustmentSchema = z.object({
	permission_key: permissionKeySchema,
	override_state: z.enum(['grant', 'deny']),
	access_scope: z.literal('all').optional()
});

export const teamInvitationCreateSchema = z.object({
	email: z
		.string()
		.trim()
		.email('Enter a valid email address.')
		.max(320)
		.transform((value) => value.toLowerCase()),
	role: assignableRoleSchema,
	permission_adjustments: z.array(invitationPermissionAdjustmentSchema).max(200).default([])
});

export const invitationIdSchema = z.string().uuid();

export const teamInvitationTokenSchema = z
	.string()
	.trim()
	.length(43, 'This invitation link is invalid.')
	.regex(/^[A-Za-z0-9_-]+$/, 'This invitation link is invalid.');

const teamInvitationPasswordSchema = z
	.string()
	.min(8, 'Use at least 8 characters for the password.')
	.max(72, 'Use no more than 72 characters for the password.');

export const teamInvitationAcceptSchema = z
	.object({
		token: teamInvitationTokenSchema,
		email: z
			.string()
			.trim()
			.email('Enter a valid email address.')
			.max(320)
			.transform((value) => value.toLowerCase()),
		password: teamInvitationPasswordSchema,
		password_confirmation: z.string().min(1, 'Confirm your new password.').max(72)
	})
	.refine((value) => value.password === value.password_confirmation, {
		path: ['password_confirmation'],
		message: 'Passwords do not match.'
	});

export const teamInvitationReplaceEmailSchema = z.object({
	email: z
		.string()
		.trim()
		.email('Enter a valid email address.')
		.max(320)
		.transform((value) => value.toLowerCase())
});

// The revision the editor was shown. The command compares it and refuses a stale editor, so a save
// without one is a save that could silently overwrite somebody else's.
const expectedAccessRevisionSchema = z
	.number()
	.int('Reload this person before saving.')
	.nonnegative('Reload this person before saving.');

export const memberRoleChangeSchema = z.object({
	role: assignableRoleSchema,
	keep_adjustments: z.boolean(),
	expected_access_revision: expectedAccessRevisionSchema
});

// The whole adjustment set, because the screen saves a section rather than one control. An empty list
// means this person keeps no individual adjustments at all.
export const memberPermissionsSaveSchema = z.object({
	expected_access_revision: expectedAccessRevisionSchema,
	adjustments: z
		.array(
			z.object({
				control_id: z.string().trim().min(1).max(80),
				override_state: z.enum(['grant', 'deny'])
			})
		)
		.max(200, 'That is more adjustments than one person can have.')
});

const expectedProfileRevisionSchema = z
	.number()
	.int('Reload this person before saving.')
	.nonnegative('Reload this person before saving.');

export const memberProfileSaveSchema = z.object({
	full_name: z.string().trim().max(160, 'Use no more than 160 characters.').default(''),
	work_phone: z.string().trim().max(40, 'Use no more than 40 characters.').default(''),
	job_title: z.string().trim().max(80, 'Use no more than 80 characters.').default(''),
	schedule_color: z
		.string()
		.trim()
		.regex(/^(|#[0-9A-Fa-f]{6})$/, 'Choose a valid scheduling color.')
		.default(''),
	expected_profile_revision: expectedProfileRevisionSchema
});

// What an employee costs the business per hour, in whole cents. Null is a real answer and not the same as
// zero: nobody has said yet what this person costs, and job costing reports their hours as unrated rather
// than valuing them at nothing. The ceiling is the column's own check restated.
export const memberCostRateSchema = z.object({
	cost_per_hour_minor: z
		.number()
		.int('Enter a whole amount.')
		.min(0, 'An hourly cost cannot be negative.')
		.max(100_000_000, 'That hourly cost is too large.')
		.nullable()
});

// When one person can work. Both halves of the section share a revision, so both schemas carry it.
const expectedAvailabilityRevisionSchema = z
	.number()
	.int('Reload this person before saving.')
	.nonnegative('Reload this person before saving.');

// HH:MM, the same shape the Business Hours form sends. Seconds are not a thing anyone schedules by.
const clockTimeSchema = z
	.string()
	.trim()
	.regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Enter a time like 08:00.');

// A day is either off, or worked between two times. The database restates this as a CHECK, so a payload that
// slips past a future edit here still cannot be stored.
const availabilityDaySchema = z
	.object({
		weekday: z.number().int().min(0, 'Pick a day.').max(6, 'Pick a day.'),
		is_working: z.boolean(),
		starts_at: clockTimeSchema.nullable().default(null),
		ends_at: clockTimeSchema.nullable().default(null)
	})
	.refine((day) => !day.is_working || (day.starts_at !== null && day.ends_at !== null), {
		message: 'A working day needs a start and an end.',
		path: ['starts_at']
	})
	.refine((day) => !day.is_working || (day.ends_at ?? '') > (day.starts_at ?? ''), {
		message: 'The finish has to be after the start.',
		path: ['ends_at']
	});

// Seven days or none. An empty list is how the screen says "nobody has set a pattern" again, which is a real
// answer and not the same as a week of days off.
export const memberWeeklyAvailabilitySchema = z.object({
	pattern: z
		.array(availabilityDaySchema)
		.refine((days) => days.length === 0 || days.length === 7, {
			message: 'A working week has to cover every day.'
		})
		.refine((days) => new Set(days.map((day) => day.weekday)).size === days.length, {
			message: 'Each day can only appear once.'
		}),
	expected_availability_revision: expectedAvailabilityRevisionSchema
});

export const memberAvailabilityExceptionSchema = z
	.object({
		exception_date: z
			.string()
			.trim()
			.regex(/^\d{4}-\d{2}-\d{2}$/, 'Pick a date.'),
		is_working: z.boolean(),
		starts_at: clockTimeSchema.nullable().default(null),
		ends_at: clockTimeSchema.nullable().default(null),
		reason: z.string().trim().max(120, 'Use no more than 120 characters.').default(''),
		expected_availability_revision: expectedAvailabilityRevisionSchema
	})
	.refine((entry) => !entry.is_working || (entry.starts_at !== null && entry.ends_at !== null), {
		message: 'Say which hours are worked that day.',
		path: ['starts_at']
	})
	.refine((entry) => !entry.is_working || (entry.ends_at ?? '') > (entry.starts_at ?? ''), {
		message: 'The finish has to be after the start.',
		path: ['ends_at']
	});

export const memberAvailabilityExceptionDeleteSchema = z.object({
	exception_id: z.string().uuid(),
	expected_availability_revision: expectedAvailabilityRevisionSchema
});

export function zodAccessFieldErrors(error: z.ZodError) {
	return Object.fromEntries(
		error.issues.map((issue) => [String(issue.path[0] ?? 'form'), issue.message] as const)
	);
}
