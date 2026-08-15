import { z } from 'zod';

export const ownerLoginSchema = z.object({
	email: z.string().trim().email('Enter a valid email address.').max(254),
	password: z.string().min(1, 'Enter your password.').max(256)
});

export const ownerReconfirmSchema = z.object({
	password: z.string().min(1, 'Enter your password.').max(256)
});

const calendarDate = z
	.string()
	.regex(/^\d{4}-\d{2}-\d{2}$/, 'Use a valid calendar date.')
	.refine((value) => {
		const date = new Date(`${value}T00:00:00Z`);
		return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
	}, 'Use a valid calendar date.');

export const suspensionCategorySchema = z.enum([
	'nonpayment',
	'payment_dispute',
	'security',
	'support',
	'other'
]);

export const organizationLifecycleSchema = z.discriminatedUnion('status', [
	z.object({
		status: z.literal('suspended'),
		suspension_category: suspensionCategorySchema,
		reason: z.string().trim().min(1, 'Enter a private reason.').max(1000),
		idempotency_key: z.string().uuid('Start a new status change and try again.')
	}),
	z.object({
		status: z.literal('active'),
		reason: z.string().trim().min(1, 'Enter a private reason.').max(1000),
		idempotency_key: z.string().uuid('Start a new status change and try again.')
	})
]);

export const organizationLegacyReconciliationSchema = z.discriminatedUnion('status', [
	z.object({
		status: z.literal('suspended'),
		suspension_category: suspensionCategorySchema,
		reason: z.string().trim().min(1, 'Enter a reconciliation reason.').max(1000),
		idempotency_key: z.string().uuid('Start a new reconciliation and try again.')
	}),
	z.object({
		status: z.literal('active'),
		reason: z.string().trim().min(1, 'Enter a reconciliation reason.').max(1000),
		idempotency_key: z.string().uuid('Start a new reconciliation and try again.')
	})
]);

const freeAccessCommandBase = z.object({
	reason: z.string().trim().min(1, 'Enter a private reason.').max(500),
	idempotency_key: z.string().uuid('Start a new free access change and try again.')
});

export const freeAccessChangeSchema = z.discriminatedUnion('action', [
	freeAccessCommandBase.extend({
		action: z.literal('grant'),
		starts_at: calendarDate,
		access_until_date: calendarDate.nullish()
	}),
	freeAccessCommandBase.extend({
		action: z.literal('extend'),
		grant_id: z.string().uuid(),
		access_until_date: calendarDate
	}),
	freeAccessCommandBase.extend({
		action: z.literal('convert_to_forever'),
		grant_id: z.string().uuid()
	}),
	freeAccessCommandBase.extend({
		action: z.literal('end'),
		grant_id: z.string().uuid()
	})
]);

const commercialCommandBase = z.object({
	idempotency_key: z.string().uuid('Start a new commercial action and try again.'),
	paid_through_effect: z.enum(['set', 'unchanged']),
	paid_through_date: calendarDate.nullish(),
	private_reference: z.string().trim().min(1, 'Enter the private payment reference.').max(240),
	private_reason: z.string().trim().min(1, 'Enter a private reason.').max(1000).nullish()
});

function requireConfirmedPaidThrough(
	value: { paid_through_effect: 'set' | 'unchanged'; paid_through_date?: string | null },
	context: z.RefinementCtx
) {
	if (value.paid_through_effect === 'set' && !value.paid_through_date) {
		context.addIssue({
			code: 'custom',
			path: ['paid_through_date'],
			message: 'Confirm the resulting paid-through date.'
		});
	}
	if (value.paid_through_effect === 'unchanged' && value.paid_through_date) {
		context.addIssue({
			code: 'custom',
			path: ['paid_through_date'],
			message: 'Remove the date when confirming no paid-through change.'
		});
	}
}

const positiveAmount = z
	.number()
	.int()
	.positive('Enter an amount greater than zero.')
	.max(100_000_000);

const renewalCommercialCommandSchema = commercialCommandBase
	.extend({
		action: z.literal('renewal'),
		amount_usd_cents: positiveAmount,
		reactivate: z.boolean()
	})
	.superRefine(requireConfirmedPaidThrough);

const correctionCommercialCommandSchema = commercialCommandBase
	.extend({
		action: z.literal('correction'),
		original_event_id: z.string().uuid('Choose the original payment or renewal.'),
		private_reason: z.string().trim().min(1, 'Enter a private reason.').max(1000),
		amount_usd_cents: z.number().int().min(-100_000_000).max(100_000_000).refine(Boolean, {
			message: 'The corrected amount cannot be zero.'
		})
	})
	.superRefine(requireConfirmedPaidThrough);

const adjustmentCommercialCommandBase = commercialCommandBase.extend({
	original_event_id: z.string().uuid('Choose the original payment or renewal.'),
	private_reason: z.string().trim().min(1, 'Enter a private reason.').max(1000),
	amount_usd_cents: positiveAmount
});

const refundCommercialCommandSchema = adjustmentCommercialCommandBase
	.extend({ action: z.literal('refund') })
	.superRefine(requireConfirmedPaidThrough);

const reversalCommercialCommandSchema = adjustmentCommercialCommandBase
	.extend({ action: z.literal('reversal') })
	.superRefine(requireConfirmedPaidThrough);

export const organizationCommercialCommandSchema = z.union([
	renewalCommercialCommandSchema,
	correctionCommercialCommandSchema,
	refundCommercialCommandSchema,
	reversalCommercialCommandSchema
]);

export const teamProfileCorrectionSchema = z
	.object({
		full_name: z.string().trim().min(1, 'Enter a name.').max(160).nullish(),
		email: z.string().trim().toLowerCase().email('Enter a valid email address.').max(254).nullish(),
		reason: z.string().trim().min(1, 'Enter a correction reason.').max(1000),
		idempotency_key: z.string().uuid('Start a new correction and try again.')
	})
	.refine((value) => value.full_name != null || value.email != null, {
		message: 'Correct the name, the email, or both.',
		path: ['full_name']
	});

export const organizationClosureStartSchema = z.object({
	reason: z.string().trim().min(1, 'Enter a private reason.').max(1000),
	typed_organization_name: z.string().trim().min(1, 'Type the organization name to confirm.').max(200),
	idempotency_key: z.string().uuid('Start a new closure and try again.')
});

export const organizationClosureRestoreSchema = z.object({
	restoration_evidence_note: z
		.string()
		.trim()
		.min(1, 'Describe how you verified this restoration.')
		.max(1000),
	idempotency_key: z.string().uuid('Start a new restoration and try again.')
});

export const organizationEarlyPurgeSchema = z.object({
	organization_id: z.string().uuid('Choose a valid organization.'),
	typed_organization_name: z.string().trim().min(1, 'Type the organization name to confirm.').max(200)
});

export const administratorEmailRecoverySchema = z.object({
	new_email: z.string().trim().toLowerCase().email('Enter a valid email address.').max(254),
	evidence_summary: z
		.string()
		.trim()
		.min(1, 'Describe how you verified this person.')
		.max(1000),
	reason: z.string().trim().min(1, 'Enter a recovery reason.').max(1000),
	idempotency_key: z.string().uuid('Start a new recovery and try again.')
});

export function zodOwnerFieldErrors(error: z.ZodError) {
	return Object.fromEntries(
		error.issues.map((issue) => [String(issue.path[0] ?? 'form'), issue.message] as const)
	);
}
