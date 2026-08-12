import { z } from 'zod';

export const packageKeySchema = z.enum(['starter', 'growth', 'elite']);
export const limitKeySchema = z.literal('employee_seats');
export const organizationIdSchema = z.string().uuid();
export const userIdSchema = z.string().uuid();
export const contractorRoleSchema = z.enum([
	'owner',
	'admin',
	'office',
	'sales',
	'field',
	'finance'
]);
export const permissionKeySchema = z
	.string()
	.trim()
	.regex(/^[a-z][a-z0-9_.-]{1,79}$/, 'Use a valid permission key.');

const isoDateTime = z.string().refine((value) => !Number.isNaN(Date.parse(value)), {
	message: 'Use a valid ISO date and time.'
});

export const packageChangeSchema = z.object({
	package_key: packageKeySchema,
	effective_at: isoDateTime.optional()
});

export const legacyPackageAssignmentSchema = z.object({
	package_version_id: z.string().uuid(),
	paid_through_date: z
		.string()
		.regex(/^\d{4}-\d{2}-\d{2}$/, 'Use a valid paid-through date.'),
	reason: z.string().trim().min(1, 'Enter a private reason.').max(500)
});

const overrideWindowSchema = z.object({
	override_state: z.enum(['on', 'off', 'inherit']),
	starts_at: isoDateTime.optional(),
	expires_at: isoDateTime.nullish()
});

export const featureOverrideSchema = overrideWindowSchema.superRefine((value, context) => {
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
		limit_value: z.number().int().nonnegative().nullable().optional(),
		is_unlimited: z.boolean().optional().default(false)
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
		if (value.override_state !== 'inherit') {
			if (value.is_unlimited && value.limit_value !== null && value.limit_value !== undefined) {
				context.addIssue({
					code: 'custom',
					path: ['limit_value'],
					message: 'Unlimited limits cannot include a numeric value.'
				});
			}
			if (!value.is_unlimited && value.limit_value === null) {
				context.addIssue({
					code: 'custom',
					path: ['limit_value'],
					message: 'Enter a numeric limit or choose unlimited.'
				});
			}
		}
	});

export const memberRoleChangeSchema = z.object({
	role: contractorRoleSchema
});

export const memberPermissionOverrideSchema = z.object({
	override_state: z.enum(['grant', 'deny', 'inherit'])
});

export function zodAccessFieldErrors(error: z.ZodError) {
	return Object.fromEntries(
		error.issues.map((issue) => [String(issue.path[0] ?? 'form'), issue.message] as const)
	);
}
