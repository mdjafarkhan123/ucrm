import { z } from 'zod';

export const ownerLoginSchema = z.object({
	email: z.string().trim().email('Enter a valid email address.').max(254),
	password: z.string().min(1, 'Enter your password.').max(256)
});

export const ownerReconfirmSchema = z.object({
	password: z.string().min(1, 'Enter your password.').max(256)
});

export const communicationDomainProvisionSchema = z
	.object({
		domain_name: z
			.string()
			.trim()
			.toLowerCase()
			.min(4)
			.max(253)
			.regex(
				/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/,
				'Enter a valid domain name.'
			),
		dns_zone: z
			.string()
			.trim()
			.toLowerCase()
			.min(4)
			.max(253)
			.regex(
				/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/,
				'Enter a valid parent DNS zone.'
			),
		purpose: z.literal('sending'),
		idempotency_key: z.string().uuid('Start a new provisioning attempt and try again.')
	})
	.superRefine((value, context) => {
		if (value.domain_name !== value.dns_zone && !value.domain_name.endsWith(`.${value.dns_zone}`)) {
			context.addIssue({
				code: 'custom',
				path: ['dns_zone'],
				message: 'The sending domain must be inside this DNS zone.'
			});
		}
	});

export const communicationDomainRecheckSchema = z.object({
	idempotency_key: z.string().uuid('Start a new domain check and try again.')
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

export const communicationDomainReplacementSchema = z
	.object({
		domain_name: communicationDomainProvisionSchema.shape.domain_name,
		dns_zone: communicationDomainProvisionSchema.shape.dns_zone,
		idempotency_key: z.string().uuid('Start a new replacement attempt and try again.')
	})
	.superRefine((value, context) => {
		if (value.domain_name !== value.dns_zone && !value.domain_name.endsWith(`.${value.dns_zone}`)) {
			context.addIssue({
				code: 'custom',
				path: ['dns_zone'],
				message: 'The sending domain must be inside this DNS zone.'
			});
		}
	});

export const communicationDomainRemovalSchema = z.object({
	confirm_domain_name: communicationDomainProvisionSchema.shape.domain_name,
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

// Communications 8.5: Jafar retrying the external (Auth + Brevo) cleanup for one stuck deletion
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

export function zodOwnerFieldErrors(error: z.ZodError) {
	return Object.fromEntries(
		error.issues.map((issue) => [String(issue.path[0] ?? 'form'), issue.message] as const)
	);
}
