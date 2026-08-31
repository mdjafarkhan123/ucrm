import { z } from 'zod';

export const packageKeySchema = z.enum(['starter', 'growth', 'elite']);
export const limitKeySchema = z.enum([
	'employee_seats',
	'operational_email_recipients',
	'essential_email_recipients',
	'website_chat_widgets',
	'website_chat_accepted_conversations',
	// Automation (Part 6B): the seven versioned limits admitted by apply_organization_limit_exception.
	'automation_active_recipes',
	'automation_max_conditions_per_recipe',
	'automation_max_steps_per_recipe',
	'automation_max_customer_messages_per_enrollment',
	'automation_min_customer_message_spacing_minutes',
	'automation_max_delay_days',
	'automation_max_enrollment_duration_days'
]);
export const organizationIdSchema = z.string().uuid();
export const userIdSchema = z.string().uuid();
export const permissionKeySchema = z
	.string()
	.trim()
	.regex(/^[a-z][a-z0-9_.-]{1,79}$/, 'Use a valid permission key.');

const isoDateTime = z.string().refine((value) => !Number.isNaN(Date.parse(value)), {
	message: 'Use a valid ISO date and time.'
});

export const packageChangeSchema = z.object({
	package_version_id: z.string().uuid(),
	reason: z.string().trim().min(1, 'Enter a private reason.').max(1000),
	idempotency_key: z.string().trim().min(8).max(200)
});

export const legacyPackageAssignmentSchema = z.object({
	package_version_id: z.string().uuid(),
	paid_through_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Use a valid paid-through date.'),
	reason: z.string().trim().min(1, 'Enter a private reason.').max(500)
});

const overrideWindowSchema = z.object({
	starts_at: isoDateTime,
	expires_at: isoDateTime.nullish(),
	reason: z.string().trim().min(1, 'Enter a private reason.').max(1000),
	idempotency_key: z.string().trim().min(8).max(200)
});

export const featureOverrideSchema = overrideWindowSchema
	.extend({ override_state: z.enum(['on', 'off', 'inherit']) })
	.superRefine((value, context) => {
		if (
			value.expires_at &&
			value.starts_at &&
			Date.parse(value.expires_at) <= Date.parse(value.starts_at)
		) {
			context.addIssue({
				code: 'custom',
				path: ['expires_at'],
				message: 'Expiry must be later than the start time.'
			});
		}
	});

export const limitOverrideSchema = overrideWindowSchema
	.extend({
		override_state: z.enum(['unlimited', 'not_included', 'numeric', 'inherit']),
		limit_value: z.number().int().nonnegative().nullable().optional()
	})
	.superRefine((value, context) => {
		if (
			value.expires_at &&
			value.starts_at &&
			Date.parse(value.expires_at) <= Date.parse(value.starts_at)
		) {
			context.addIssue({
				code: 'custom',
				path: ['expires_at'],
				message: 'Expiry must be later than the start time.'
			});
		}
		if (
			value.override_state === 'numeric' &&
			(value.limit_value === null || value.limit_value === undefined)
		) {
			context.addIssue({
				code: 'custom',
				path: ['limit_value'],
				message: 'Enter a numeric limit.'
			});
		}
		if (
			value.override_state !== 'numeric' &&
			value.limit_value !== null &&
			value.limit_value !== undefined
		) {
			context.addIssue({
				code: 'custom',
				path: ['limit_value'],
				message: 'Only numeric limits can include a value.'
			});
		}
	});

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

export function zodAccessFieldErrors(error: z.ZodError) {
	return Object.fromEntries(
		error.issues.map((issue) => [String(issue.path[0] ?? 'form'), issue.message] as const)
	);
}
