import { z } from 'zod';

export const ownerLoginSchema = z.object({
	email: z.string().trim().email('Enter a valid email address.').max(254),
	password: z.string().min(1, 'Enter your password.').max(256)
});

export const ownerReconfirmSchema = z.object({
	password: z.string().min(1, 'Enter your password.').max(256)
});

const domainNameSchema = z
	.string()
	.trim()
	.toLowerCase()
	.min(4)
	.max(253)
	.regex(
		/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/,
		'Enter a valid domain name.'
	);

export const communicationDomainRecheckSchema = z.object({
	idempotency_key: z.string().uuid('Start a new domain check and try again.')
});

// Marketing M6d: the owner's branded click-link controls. Turning on runs the same reconciliation Check does;
// turning off and removing return links to Amazon's default address first.
export const marketingClickDomainChangeSchema = z.object({
	action: z.enum(['turn_on', 'turn_off', 'remove']),
	idempotency_key: z.string().uuid('Start the change again and try again.')
});

// A1-D managed activation: the owner supplies only the root domain. UCRM derives mail.<root> for sending
// and reply.<root> for receiving, resolves the Cloudflare zone by that exact apex, and reconciles both.
export const communicationDomainActivationSchema = z.object({
	root_domain: z
		.string()
		.trim()
		.toLowerCase()
		.min(4)
		.max(253)
		.regex(
			/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/,
			'Enter a valid root domain.'
		),
	idempotency_key: z.string().uuid('Start a new activation attempt and try again.')
});

export const communicationDomainRemovalSchema = z.object({
	confirm_domain_name: domainNameSchema,
	reason: z.string().trim().min(1, 'Enter a private removal reason.').max(500),
	expected_impact: z.object({
		live_sender_count: z.number().int().min(0),
		live_replacement_count: z.number().int().min(0)
	}),
	idempotency_key: z.string().uuid('Start a new removal attempt and try again.')
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

// Package builder P4b: the Billing workspace's commands, one per ledger command (ADR 0003 decision 6).
// Money is whole US cents; every command carries the idempotency key the dialog made when it opened.
const billingIdempotencyKey = z
	.string()
	.uuid('Start again from the Billing tab and try once more.');
const billingAmount = z
	.number()
	.int('Enter an amount in dollars and cents.')
	.positive('Enter an amount greater than zero.')
	.max(100_000_000);
const billingReason = z
	.string()
	.trim()
	.min(3, 'Enter a reason of at least 3 characters.')
	.max(1000);
const freeAccessReason = z
	.string()
	.trim()
	.min(3, 'Enter a reason of at least 3 characters.')
	.max(500, 'Keep the reason under 500 characters.');
const billingMethod = z.string().trim().min(1, 'Enter how the money was paid.').max(80);
const packageBillingInterval = z.enum(['month', 'year'], {
	message: 'Choose monthly or yearly billing.'
});
const packageChangeTiming = z.enum(['next_renewal', 'now'], {
	message: 'Choose when the change starts.'
});

export const organizationBillingCommandSchema = z.discriminatedUnion('action', [
	z.object({
		action: z.literal('add_charge'),
		idempotency_key: billingIdempotencyKey,
		period_start: calendarDate.nullish()
	}),
	z.object({
		action: z.literal('record_payment'),
		idempotency_key: billingIdempotencyKey,
		received_on: calendarDate,
		amount_usd_cents: billingAmount,
		method: billingMethod,
		private_reference: z.string().trim().min(1, 'Enter the payment reference.').max(240),
		note: z.string().trim().max(1000).nullish(),
		applications: z
			.array(z.object({ charge_id: z.string().uuid(), amount_usd_cents: billingAmount }))
			.max(24)
	}),
	z.object({
		action: z.literal('apply_credit'),
		idempotency_key: billingIdempotencyKey,
		receipt_id: z.string().uuid(),
		charge_id: z.string().uuid('Choose the charge to pay.'),
		amount_usd_cents: billingAmount
	}),
	z.object({
		action: z.literal('refund'),
		idempotency_key: billingIdempotencyKey,
		receipt_id: z.string().uuid(),
		refunded_on: calendarDate,
		amount_usd_cents: billingAmount,
		method: billingMethod,
		private_reference: z.string().trim().max(240).nullish(),
		reason: billingReason
	}),
	z.object({
		action: z.literal('void'),
		idempotency_key: billingIdempotencyKey,
		record_kind: z.enum(['charge', 'receipt', 'application', 'refund']),
		record_id: z.string().uuid(),
		reason: billingReason
	}),
	z.object({
		action: z.literal('correct_payment'),
		idempotency_key: billingIdempotencyKey,
		original_receipt_id: z.string().uuid(),
		received_on: calendarDate,
		amount_usd_cents: billingAmount,
		method: billingMethod,
		private_reference: z.string().trim().min(1, 'Enter the payment reference.').max(240),
		note: z.string().trim().max(1000).nullish(),
		reason: billingReason
	}),
	z.object({
		action: z.literal('confirm_coverage'),
		idempotency_key: billingIdempotencyKey,
		charge_id: z.string().uuid(),
		covered_from: calendarDate,
		covered_through: calendarDate
	}),
	z.object({
		action: z.literal('adjust_paid_through'),
		idempotency_key: billingIdempotencyKey,
		paid_through_date: calendarDate,
		reason: billingReason
	}),
	// Package builder P5c: free access is dated covered time without payment (P5a commands).
	z.object({
		action: z.literal('grant_free_access'),
		idempotency_key: billingIdempotencyKey,
		starts_on: calendarDate,
		ends_on: calendarDate,
		reason: freeAccessReason
	}),
	z.object({
		action: z.literal('extend_free_access'),
		idempotency_key: billingIdempotencyKey,
		grant_id: z.string().uuid(),
		ends_on: calendarDate,
		reason: freeAccessReason
	}),
	z.object({
		action: z.literal('end_free_access'),
		idempotency_key: billingIdempotencyKey,
		grant_id: z.string().uuid(),
		reason: freeAccessReason
	}),
	// Package builder P8b: the change Jafar reviewed, with the date and amounts the preview showed. The
	// database refuses it if any of them has moved since.
	z.object({
		action: z.literal('change_package'),
		idempotency_key: billingIdempotencyKey,
		edition_id: z.string().uuid('Choose a package.'),
		billing_interval: packageBillingInterval,
		timing: packageChangeTiming,
		expected_effective_date: calendarDate,
		expected_credit_usd_cents: z.number().int().min(0).max(100_000_000),
		expected_charge_usd_cents: z.number().int().min(0).max(100_000_000),
		reason: freeAccessReason
	}),
	z.object({
		action: z.literal('cancel_package_change'),
		idempotency_key: billingIdempotencyKey,
		agreement_id: z.string().uuid(),
		reason: freeAccessReason
	}),
	z.object({
		action: z.literal('apply_change_credit'),
		idempotency_key: billingIdempotencyKey,
		credit_note_id: z.string().uuid(),
		charge_id: z.string().uuid('Choose the charge to pay.'),
		amount_usd_cents: billingAmount
	})
]);

// What the change dialog asks the database to preview before Jafar confirms.
export const packageChangePreviewSchema = z.object({
	edition_id: z.string().uuid('Choose a package.'),
	billing_interval: packageBillingInterval,
	timing: packageChangeTiming
});

// Package builder P8b: a temporary exception switches one feature on or off, or sets one limit, for a
// reasoned, dated period. Ending one early keeps its record.
const exceptionReason = z
	.string()
	.trim()
	.min(3, 'Enter a reason of at least 3 characters.')
	.max(1000, 'Keep the reason under 1,000 characters.');
const exceptionKey = z
	.string()
	.trim()
	.regex(/^[a-z][a-z0-9_.]{1,79}$/, 'Choose a feature or limit.');

export const packageExceptionCommandSchema = z.discriminatedUnion('action', [
	z
		.object({
			action: z.literal('add'),
			idempotency_key: billingIdempotencyKey,
			target: z.enum(['capability', 'allowance']),
			key: exceptionKey,
			capability_state: z.enum(['on', 'off']).nullish(),
			allowance_state: z.enum(['numeric', 'unlimited', 'not_included']).nullish(),
			allowance_value: z
				.number()
				.int('Enter a whole number.')
				.min(0, 'Enter a number of zero or more.')
				.max(10_000_000)
				.nullish(),
			starts_at: z.iso.datetime({ offset: true, message: 'Choose when it starts.' }),
			ends_at: z.iso.datetime({ offset: true, message: 'Choose when it ends.' }),
			reason: exceptionReason
		})
		.superRefine((value, context) => {
			if (value.target === 'capability' && !value.capability_state)
				context.addIssue({
					code: 'custom',
					path: ['capability_state'],
					message: 'Choose on or off.'
				});
			if (value.target === 'allowance' && !value.allowance_state)
				context.addIssue({
					code: 'custom',
					path: ['allowance_state'],
					message: 'Choose a number, unlimited, or not included.'
				});
			if (
				value.target === 'allowance' &&
				value.allowance_state === 'numeric' &&
				(value.allowance_value === null || value.allowance_value === undefined)
			)
				context.addIssue({
					code: 'custom',
					path: ['allowance_value'],
					message: 'Enter the limit.'
				});
			if (Date.parse(value.ends_at) <= Date.parse(value.starts_at))
				context.addIssue({
					code: 'custom',
					path: ['ends_at'],
					message: 'Choose an end after the start.'
				});
		}),
	z.object({
		action: z.literal('end'),
		idempotency_key: billingIdempotencyKey,
		exception_id: z.string().uuid(),
		reason: exceptionReason
	})
]);

export type PackageExceptionCommand = z.infer<typeof packageExceptionCommandSchema>;

export type OrganizationBillingCommand = z.infer<typeof organizationBillingCommandSchema>;

// Actions that take money back, cancel a record, or move access dates by hand (free access included) need a
// fresh password.
export const billingStepUpActions: ReadonlySet<OrganizationBillingCommand['action']> = new Set([
	'refund',
	'void',
	'correct_payment',
	'adjust_paid_through',
	'grant_free_access',
	'extend_free_access',
	'end_free_access'
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
	typed_organization_name: z
		.string()
		.trim()
		.min(1, 'Type the organization name to confirm.')
		.max(200),
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
	typed_organization_name: z
		.string()
		.trim()
		.min(1, 'Type the organization name to confirm.')
		.max(200)
});

// Communications 8.5: Jafar retrying the external (Auth + Amazon SES) cleanup for one stuck deletion
// receipt. The receipt is the only handle left once the organization is already purged, so the retry
// is keyed by its operation_id alone.
export const organizationCleanupRetrySchema = z.object({
	operation_id: z.string().uuid('Choose a valid deletion to retry.')
});

export const communicationEmailSendingPauseSchema = z.object({
	engage: z.boolean(),
	reason: z.string().trim().min(3, 'Enter a reason of at least 3 characters.').max(500)
});

const websiteChatAuthorityReasonSchema = z
	.string()
	.trim()
	.min(3, 'Enter a reason of at least 3 characters.')
	.max(500, 'Keep the reason under 500 characters.');

export const websiteChatSuspensionSchema = z.object({
	engage: z.boolean(),
	reason: websiteChatAuthorityReasonSchema,
	idempotency_key: z.string().uuid('Start a new suspension change and try again.')
});

export const websiteChatTokenRotationSchema = z.object({
	widget_id: z.string().uuid('Choose a valid Website Chat widget.'),
	expected_revision: z.number().int().min(1),
	reason: websiteChatAuthorityReasonSchema,
	idempotency_key: z.string().uuid('Start a new token rotation and try again.')
});

// Automation authority (Part 6B, slice 3b). Two independent axes -- operational and security -- each
// toggled with a safe reason and an idempotency key, mirroring the Website Chat suspension shape.
export const automationAuthoritySchema = z.object({
	axis: z.enum(['operational', 'security'], {
		error: 'Choose the operational or security authority axis.'
	}),
	engage: z.boolean(),
	reason: z
		.string()
		.trim()
		.min(3, 'Enter a reason of at least 3 characters.')
		.max(500, 'Keep the reason under 500 characters.'),
	idempotency_key: z.string().uuid('Start a new authority change and try again.')
});

const reputationSignalSchema = z.enum(['complaint', 'hard_bounce', 'unsubscribe'], {
	error: 'Choose complaint, hard bounce, or unsubscribe.'
});

const reputationWindowSchema = z.enum(['rolling_24h', 'rolling_7d'], {
	error: 'Choose the rolling 24-hour or rolling 7-day window.'
});

// Rates are percentages stored as numeric(7,4) -- 0.1000 means 0.10% of accepted recipients.
const reputationRateSchema = z
	.number()
	.min(0, 'A rate cannot be negative.')
	.max(100, 'A rate cannot exceed 100%.')
	.nullable();

const reputationReasonSchema = z
	.string()
	.trim()
	.min(3, 'Enter a reason of at least 3 characters.')
	.max(500);

export const communicationEmailReputationPlatformThresholdSchema = z.object({
	signal: reputationSignalSchema,
	window_key: reputationWindowSchema,
	window_hours: z
		.number()
		.int()
		.min(1, 'A window is at least one hour.')
		.max(2160, 'A window cannot exceed 90 days.')
		.nullable()
		.default(null),
	warn_rate: reputationRateSchema.default(null),
	pause_rate: reputationRateSchema.default(null),
	min_sample_recipients: z.number().int().min(1).max(10_000_000).nullable().default(null),
	min_event_count: z.number().int().min(1).max(1_000_000).nullable().default(null),
	reason: reputationReasonSchema,
	confirm_platform_change: z.boolean().default(false)
});

// An organization override may only tighten the platform ceiling. Leaving every value null clears it.
export const communicationEmailReputationOverrideSchema = z.object({
	signal: reputationSignalSchema,
	window_key: reputationWindowSchema,
	warn_rate: reputationRateSchema.default(null),
	pause_rate: reputationRateSchema.default(null),
	min_sample_recipients: z.number().int().min(1).max(10_000_000).nullable().default(null),
	min_event_count: z.number().int().min(1).max(1_000_000).nullable().default(null),
	reason: reputationReasonSchema
});

export const communicationEmailReputationResumeSchema = z.object({
	reason: reputationReasonSchema,
	confirm_remediation: z.boolean().default(false),
	// Which automatic pause to lift: the operational one (optional follow-ups) or the Marketing-only one.
	stream: z.enum(['operational', 'marketing']).default('operational')
});

// Jafar approving or denying a pending complaint-suppression removal request (Communications 7.2).
// A denial must carry a note the requester will read; an approval may add one.
export const communicationEmailSuppressionRemovalDecisionSchema = z
	.object({
		decision: z.enum(['approve', 'deny'], { error: 'Choose approve or deny.' }),
		note: z
			.string()
			.trim()
			.max(1000, 'Keep the note under 1,000 characters.')
			.optional()
			.transform((value) => value || undefined)
	})
	.refine((value) => value.decision === 'approve' || Boolean(value.note), {
		error: 'Add a note explaining why the request is denied.',
		path: ['note']
	});

// Communications 7.5a: platform sending-capacity controls. Both changes are platform safety
// settings, so both carry an explicit confirmation and a reason kept in the owner audit log.
const sendingCapacityReasonSchema = z
	.string()
	.trim()
	.min(3, 'Enter a reason of at least 3 characters.')
	.max(500);

export const communicationEmailWarmupStageSchema = z.object({
	kind: z.literal('warmup'),
	stage_key: z.enum(['days_1_3', 'days_4_7', 'days_8_14'], {
		error: 'Choose a warm-up stage.'
	}),
	daily_ceiling: z
		.number()
		.int()
		.min(0, 'A ceiling cannot be negative.')
		.max(10_000_000, 'A ceiling cannot exceed 10,000,000.'),
	reason: sendingCapacityReasonSchema,
	confirm_platform_change: z.boolean().default(false)
});

export const communicationEmailShortTermRateSchema = z.object({
	kind: z.literal('short_term'),
	window_minutes: z
		.number()
		.int()
		.min(1, 'A window is at least one minute.')
		.max(1440, 'A window cannot exceed 24 hours.'),
	max_recipients: z
		.number()
		.int()
		.min(1, 'The ceiling is at least one recipient.')
		.max(10_000_000, 'The ceiling cannot exceed 10,000,000.'),
	reason: sendingCapacityReasonSchema,
	confirm_platform_change: z.boolean().default(false)
});

// Communications 7.5b: the platform provider-period capacity and the essential reserve. `capacity`
// is nullable -- clearing it turns the ceiling off.
export const communicationEmailProviderCapacitySchema = z.object({
	kind: z.literal('provider_capacity'),
	capacity: z
		.number()
		.int()
		.min(1, 'A capacity is at least one recipient.')
		.max(1_000_000_000, 'A capacity cannot exceed 1,000,000,000.')
		.nullable(),
	reserve_percent: z
		.number()
		.int()
		.min(0, 'A reserve cannot be negative.')
		.max(100, 'A reserve cannot exceed 100 percent.'),
	reason: sendingCapacityReasonSchema,
	confirm_platform_change: z.boolean().default(false)
});

export const communicationEmailSendingCapacitySchema = z.discriminatedUnion('kind', [
	communicationEmailWarmupStageSchema,
	communicationEmailShortTermRateSchema,
	communicationEmailProviderCapacitySchema
]);

// Jafar retrying or cancelling one stuck message (Communications 7.6a). The database command enforces
// the same 3-1000 character reason; keeping it here turns a would-be 409 into a field error.
export const communicationMessageRecoveryActionSchema = z.object({
	action: z.enum(['retry', 'cancel'], { error: 'Choose retry or cancel.' }),
	reason: z
		.string()
		.trim()
		.min(3, 'Enter a reason of at least 3 characters.')
		.max(1000, 'Keep the reason under 1,000 characters.')
});

export const administratorEmailRecoverySchema = z.object({
	new_email: z.string().trim().toLowerCase().email('Enter a valid email address.').max(254),
	evidence_summary: z.string().trim().min(1, 'Describe how you verified this person.').max(1000),
	reason: z.string().trim().min(1, 'Enter a recovery reason.').max(1000),
	idempotency_key: z.string().uuid('Start a new recovery and try again.')
});

// Stage 2C-5a: the owner confirms or rejects an offsite SMS credit top-up request. Confirming settles a
// positive minor-unit amount (the DB caps the resulting balance); rejecting requires a reason. The
// database command enforces the same rules, so validating here turns a would-be 409 into a field error.
export const communicationSmsCreditTopupDecisionSchema = z.discriminatedUnion('action', [
	z.object({
		action: z.literal('confirm'),
		settled_amount_minor: z
			.number()
			.int('Enter a whole amount in minor units.')
			.positive('Enter an amount greater than zero.')
			.max(100_000_000, 'That amount is too large.'),
		decision_reason: z.string().trim().max(1000, 'Keep the note under 1,000 characters.').optional()
	}),
	z.object({
		action: z.literal('reject'),
		decision_reason: z
			.string()
			.trim()
			.min(3, 'Enter a reason of at least 3 characters.')
			.max(1000, 'Keep the reason under 1,000 characters.')
	})
]);

// Stage 2C-5b: the owner's money/control layer for one organization's SMS holds, promotional credit, and
// standalone adjustments/refunds. Every reason mirrors the database command's own non-empty check, so a bad
// request turns into a field error instead of a 409. Grant/adjustment/refund also carry the idempotency key
// the retry-safe commands require (see 20260917130000); hold place/release need none -- they are naturally
// idempotent (a duplicate active hold or a second release is refused by the command itself).
const smsControlReasonSchema = z
	.string()
	.trim()
	.min(3, 'Enter a reason of at least 3 characters.')
	.max(2000, 'Keep the reason under 2,000 characters.');

const smsMoneyIdempotencyKeySchema = z.string().uuid('Start a new action and try again.');

const smsMoneyAmountSchema = z
	.number()
	.int('Enter a whole amount in minor units.')
	.positive('Enter an amount greater than zero.')
	.max(100_000_000, 'That amount is too large.');

export const communicationSmsHoldPlacementSchema = z.object({
	scope: z.enum(['organization', 'provider'], {
		error: 'Choose the organization or provider hold scope.'
	}),
	reason: smsControlReasonSchema
});

export const communicationSmsHoldReleaseSchema = z.object({
	release_reason: smsControlReasonSchema
});

export const communicationSmsPromotionalCreditGrantSchema = z.object({
	amount_minor: smsMoneyAmountSchema,
	expires_at: z
		.string()
		.refine((value) => !Number.isNaN(Date.parse(value)), 'Enter a valid expiry date and time.')
		.refine((value) => Date.parse(value) > Date.now(), 'The expiry must be in the future.'),
	reason: smsControlReasonSchema,
	idempotency_key: smsMoneyIdempotencyKeySchema
});

export const communicationSmsPromotionalCreditRevokeSchema = z.object({
	reason: smsControlReasonSchema
});

export const communicationSmsAdjustmentSchema = z.object({
	amount_minor: z
		.number()
		.int('Enter a whole amount in minor units.')
		.max(100_000_000, 'That amount is too large.')
		.min(-100_000_000, 'That amount is too large.')
		.refine((value) => value !== 0, 'An adjustment must move a non-zero amount.'),
	reason: smsControlReasonSchema,
	idempotency_key: smsMoneyIdempotencyKeySchema
});

export const communicationSmsRefundSchema = z.object({
	amount_minor: smsMoneyAmountSchema,
	reason: smsControlReasonSchema,
	idempotency_key: smsMoneyIdempotencyKeySchema
});

// Stage 2C-5c: the owner's registration, mode and sender-capability layer for one organization's SMS
// readiness. None of these are money actions or on the step-up list (docs/jafar-organization-management-
// mission.md "High-impact action security"), so each carries only a reason/confirmation, not step-up --
// "carrier submission or resubmission" is explicitly a routine action there. Platform-scoped actions (a
// global retail rate, a platform-wide hold) write to platform_audit_events instead of access_audit_events,
// which keeps organization_id NOT NULL by design.
const smsCountryCodeSchema = z
	.string()
	.trim()
	.toUpperCase()
	.regex(/^[A-Z]{2}$/, 'Enter a 2-letter country code.');

const smsSenderTypeSchema = z.enum(['long_code', 'toll_free', 'short_code', 'alphanumeric'], {
	error: 'Choose a sender type.'
});

const smsModeSchema = z.enum(['off', 'operational'], { error: 'Choose off or operational.' });

export const communicationSmsRegistrationStartSchema = z.object({
	country_code: smsCountryCodeSchema,
	sender_type: smsSenderTypeSchema,
	use_case: z
		.string()
		.trim()
		.min(1, 'Enter the use case.')
		.max(200, 'Keep the use case under 200 characters.')
});

// Mirrors the database command's own rule: an approved outcome always names the provider outcome, an
// action_needed outcome always names the fixes required.
export const communicationSmsRegistrationOutcomeSchema = z.discriminatedUnion('status', [
	z.object({ status: z.literal('approved'), provider_outcome: smsControlReasonSchema }),
	z.object({ status: z.literal('action_needed'), required_fixes: smsControlReasonSchema })
]);

export const communicationSmsRegistrationCheckSchema = z.object({
	detail: z
		.string()
		.trim()
		.max(2000, 'Keep the note under 2,000 characters.')
		.optional()
		.transform((value) => value || undefined)
});

export const communicationSmsSenderCapabilitiesSchema = z.object({
	country_code: smsCountryCodeSchema,
	sender_type: smsSenderTypeSchema,
	capable_sms: z.boolean(),
	capable_mms: z.boolean().default(false),
	capable_voice: z.boolean().default(false),
	registration_id: z.string().uuid().optional()
});

export const communicationSmsOrgModeSchema = z
	.object({
		package_max_mode: smsModeSchema.optional(),
		chosen_mode: smsModeSchema.optional(),
		override_mode: smsModeSchema.optional(),
		override_reason: z
			.string()
			.trim()
			.max(2000, 'Keep the reason under 2,000 characters.')
			.optional(),
		clear_override: z.boolean().default(false)
	})
	.superRefine((value, context) => {
		if (value.clear_override && value.override_mode) {
			context.addIssue({
				code: 'custom',
				message: 'Choose either setting an override or clearing it, not both.',
				path: ['override_mode']
			});
		}
		if (value.override_mode && !value.clear_override && (value.override_reason?.length ?? 0) < 3) {
			context.addIssue({
				code: 'custom',
				message: 'Enter a reason of at least 3 characters.',
				path: ['override_reason']
			});
		}
		if (
			value.package_max_mode === undefined &&
			value.chosen_mode === undefined &&
			value.override_mode === undefined &&
			!value.clear_override
		) {
			context.addIssue({
				code: 'custom',
				message: 'Choose at least one change to make.',
				path: ['form']
			});
		}
	});

// Stage 2C-5c (platform-scoped): a platform-wide outbound-SMS hold is an emergency control (docs/jafar-
// organization-management-mission.md "High-impact action security" -- "platform-wide emergency controls"),
// so placing or releasing one requires the same step-up as an organization/provider hold. Publishing a new
// retail rate is routine: it moves no money immediately and only prices sends that happen later, the same
// treatment as a package change, so it carries a reason but no step-up.
export const communicationSmsPlatformHoldPlacementSchema = z.object({
	reason: smsControlReasonSchema
});

export const communicationSmsRetailRateSchema = z.object({
	destination: smsCountryCodeSchema,
	sender_type: smsSenderTypeSchema,
	message_unit: z.enum(['segment', 'mms'], {
		error: 'Choose a supported message unit.'
	}),
	currency_code: z
		.string()
		.trim()
		.toUpperCase()
		.regex(/^[A-Z]{3}$/, 'Enter a 3-letter currency code.')
		.default('USD'),
	retail_rate_major: z
		.number()
		.positive('Enter a rate greater than zero.')
		.max(1000, 'That rate is too large.'),
	provider_cost_major: z
		.number()
		.min(0, 'Provider cost cannot be negative.')
		.max(1000, 'That cost is too large.')
		.optional(),
	effective_from: z
		.string()
		.refine((value) => !Number.isNaN(Date.parse(value)), 'Enter a valid effective date and time.')
		.refine(
			(value) => Date.parse(value) >= Date.now(),
			'The effective date must be now or in the future.'
		)
		.optional(),
	note: z
		.string()
		.trim()
		.max(2000, 'Keep the note under 2,000 characters.')
		.optional()
		.transform((value) => value || undefined)
});

// Part 7B: the over-allowance email retail price Jafar sets, in currency major units per 1,000 recipients.
// Same immutable-version shape as communicationSmsRetailRateSchema, minus the SMS-only destination/sender/
// message-unit dimensions -- email has one price per currency, not one per route.
export const communicationEmailRetailRateSchema = z.object({
	currency_code: z
		.string()
		.trim()
		.toUpperCase()
		.regex(/^[A-Z]{3}$/, 'Enter a 3-letter currency code.')
		.default('USD'),
	retail_rate_major: z
		.number()
		.positive('Enter a rate greater than zero.')
		.max(1000, 'That rate is too large.'),
	provider_cost_major: z
		.number()
		.min(0, 'Provider cost cannot be negative.')
		.max(1000, 'That cost is too large.')
		.optional(),
	effective_from: z
		.string()
		.refine((value) => !Number.isNaN(Date.parse(value)), 'Enter a valid effective date and time.')
		.refine(
			(value) => Date.parse(value) >= Date.now(),
			'The effective date must be now or in the future.'
		)
		.optional(),
	note: z
		.string()
		.trim()
		.max(2000, 'Keep the note under 2,000 characters.')
		.optional()
		.transform((value) => value || undefined)
});

export function zodOwnerFieldErrors(error: z.ZodError) {
	return Object.fromEntries(
		error.issues.map((issue) => [String(issue.path[0] ?? 'form'), issue.message] as const)
	);
}
