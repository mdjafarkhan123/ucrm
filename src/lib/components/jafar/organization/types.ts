import type { ShownOffer } from '$lib/packages/public-package';

export type EffectiveAccess = {
	organization: { id: string; name: string; slug: string; lifecycle_status: string };
	billing: {
		paid_through_date: string | null;
		paid_through_source: string | null;
		grace_ends_at: string | null;
		is_overdue: boolean;
		is_in_grace: boolean;
	};
	// The agreement in effect and the edition it agreed to; null when the organization has none.
	package: {
		package_id: string;
		slug: string;
		edition_id: string;
		edition_number: number;
		edition_status: 'published' | 'superseded';
		name: string;
		promise: string | null;
		agreement_id: string;
		billing_interval: 'month' | 'year';
		agreed_price_usd_cents: number;
		currency: 'USD';
		effective_from: string;
	} | null;
	features: Record<string, boolean>;
	package_features: Record<string, boolean>;
	feature_overrides: Record<
		string,
		{
			state: 'on' | 'off';
			starts_at: string;
			expires_at: string | null;
			reason: string | null;
			is_legacy_import: boolean;
		}
	>;
	limits: Record<
		'employee_seats' | 'website_chat_widgets' | 'marketing_email_recipients',
		{
			state: 'unlimited' | 'not_included' | 'numeric';
			value: number | null;
			is_unlimited: boolean;
			source: 'package' | 'override';
		}
	>;
	free_access: {
		active: { grant_id: string; starts_at: string; access_until_date: string | null } | null;
		future: { grant_id: string; starts_at: string; access_until_date: string | null } | null;
	};
};
export type AccessResponse = { access: EffectiveAccess; error?: string };
export type CommercialState = {
	organization: { id: string; name: string; lifecycle_status: string };
	state: {
		paid_through_date: string | null;
		paid_through_source: string | null;
		grace_ends_at: string | null;
	} | null;
	settings: { commercial_timezone: string; timezone_source: string } | null;
	closure: { id: string; reason: string; started_at: string; deadline_at: string } | null;
	error?: string;
};

// Package builder P4b: what `owner_organization_billing` returns. Money is whole US cents; dates are
// calendar days in the organization's commercial timezone.
export type BillingCharge = {
	id: string;
	agreement_id: string;
	period_start: string;
	period_end: string;
	amount_usd_cents: number;
	// 'change' covers the rest of a period after a package change made now (P8a).
	kind: 'period' | 'change';
	applied_usd_cents: number;
	outstanding_usd_cents: number;
	status: 'unpaid' | 'partly_paid' | 'paid' | 'cancelled';
	coverage_confirmed_at: string | null;
	void_reason: string | null;
	voided_at: string | null;
	created_at: string;
};
export type BillingReceipt = {
	id: string;
	received_on: string;
	amount_usd_cents: number;
	method: string;
	private_reference: string;
	note: string | null;
	replaces_receipt_id: string | null;
	applied_usd_cents: number;
	refunded_usd_cents: number;
	unapplied_usd_cents: number;
	void_reason: string | null;
	voided_at: string | null;
	actor_owner_email: string;
	created_at: string;
};
// Money moved onto a charge, from a payment or from change credit (exactly one of the two).
export type BillingApplication = {
	id: string;
	receipt_id: string | null;
	credit_note_id: string | null;
	charge_id: string;
	amount_usd_cents: number;
	void_reason: string | null;
	voided_at: string | null;
	created_at: string;
};
export type BillingRefund = {
	id: string;
	receipt_id: string;
	refunded_on: string;
	amount_usd_cents: number;
	method: string;
	private_reference: string | null;
	reason: string;
	void_reason: string | null;
	voided_at: string | null;
	created_at: string;
};
// Package builder P8a: unused paid time a package change made now returned. Credit, not money received.
export type BillingCreditNote = {
	id: string;
	agreement_id: string;
	source_charge_id: string;
	unused_from: string;
	unused_through: string;
	amount_usd_cents: number;
	applied_usd_cents: number;
	unapplied_usd_cents: number;
	reason: string;
	created_at: string;
};
export type PackageOverLimit = {
	allowance_key: string;
	label: string;
	unit: string;
	in_use: number;
	limit: number;
};
export type BillingAgreement = {
	id: string;
	edition_id: string;
	edition_name: string;
	edition_number: number;
	package_slug: string;
	billing_interval: 'month' | 'year';
	agreed_price_usd_cents: number;
	effective_from: string;
	source: string;
	reason: string | null;
	actor_owner_email: string | null;
	created_at: string;
	cancelled_at: string | null;
	cancel_reason: string | null;
};
export type BillingUpcomingAgreement = {
	id: string;
	edition_name: string;
	edition_number: number;
	billing_interval: 'month' | 'year';
	agreed_price_usd_cents: number;
	effective_from: string;
	offer_terms: AgreementOfferTerms | null;
	// What is over the scheduled package's limits right now (P8b).
	over_limits: PackageOverLimit[];
};
export type BillingRenewalFlag = 'due_within_seven_days' | 'due_tomorrow' | 'overdue' | null;
export type OrganizationBilling = {
	commercial_timezone: string;
	today: string;
	paid_through_date: string | null;
	grace_ends_at: string | null;
	next_renewal_date: string | null;
	renewal_flag: BillingRenewalFlag;
	current_agreement: {
		id: string;
		edition_id: string;
		edition_name: string;
		edition_number: number;
		package_slug: string;
		billing_interval: 'month' | 'year';
		agreed_price_usd_cents: number;
		offer_terms: AgreementOfferTerms | null;
		effective_from: string;
	} | null;
	upcoming_agreements: BillingUpcomingAgreement[];
	totals: {
		charged_usd_cents: number;
		received_usd_cents: number;
		refunded_usd_cents: number;
		outstanding_usd_cents: number;
		due_now_usd_cents: number;
		credit_usd_cents: number;
	};
	charges: BillingCharge[];
	receipts: BillingReceipt[];
	applications: BillingApplication[];
	refunds: BillingRefund[];
	credit_notes: BillingCreditNote[];
	// Every agreement, cancelled scheduled moves included, newest first.
	agreement_history: BillingAgreement[];
	// Package builder P5c: the last covered day (paid-through or started free access), when access pauses,
	// and the current and later free-access grants.
	covered_through: string | null;
	pauses_at: string | null;
	free_access_today: boolean;
	free_access: BillingFreeAccessGrant[];
};
export type BillingFreeAccessGrant = {
	grant_id: string;
	starts_at: string;
	last_day: string;
	is_current: boolean;
	reason: string;
	granted_by: string | null;
	granted_at: string;
};
export type BillingResponse = { billing: OrganizationBilling; error?: string };
export type BillingRecordKind = 'charge' | 'receipt' | 'application' | 'refund';
// One billing command as the Billing tab sends it; the tab adds the idempotency key.
export type BillingCommandInput =
	| { action: 'add_charge'; period_start: string | null }
	| {
			action: 'record_payment';
			received_on: string;
			amount_usd_cents: number;
			method: string;
			private_reference: string;
			note: string | null;
			applications: { charge_id: string; amount_usd_cents: number }[];
	  }
	| { action: 'apply_credit'; receipt_id: string; charge_id: string; amount_usd_cents: number }
	| {
			action: 'refund';
			receipt_id: string;
			refunded_on: string;
			amount_usd_cents: number;
			method: string;
			private_reference: string | null;
			reason: string;
	  }
	| { action: 'void'; record_kind: BillingRecordKind; record_id: string; reason: string }
	| {
			action: 'correct_payment';
			original_receipt_id: string;
			received_on: string;
			amount_usd_cents: number;
			method: string;
			private_reference: string;
			note: string | null;
			reason: string;
	  }
	| { action: 'confirm_coverage'; charge_id: string; covered_from: string; covered_through: string }
	| { action: 'adjust_paid_through'; paid_through_date: string; reason: string }
	| { action: 'grant_free_access'; starts_on: string; ends_on: string; reason: string }
	| { action: 'extend_free_access'; grant_id: string; ends_on: string; reason: string }
	| { action: 'end_free_access'; grant_id: string; reason: string }
	| {
			action: 'change_package';
			edition_id: string;
			billing_interval: 'month' | 'year';
			timing: PackageChangeTiming;
			expected_effective_date: string;
			expected_credit_usd_cents: number;
			expected_charge_usd_cents: number;
			reason: string;
			offer_id: string | null;
			offer_code: string | null;
			keep_offer: boolean;
	  }
	| { action: 'cancel_package_change'; agreement_id: string; reason: string }
	| {
			action: 'apply_change_credit';
			credit_note_id: string;
			charge_id: string;
			amount_usd_cents: number;
	  };
// Which billing dialog is open, and what it was opened from.
export type BillingDialogState =
	| { kind: 'add_charge' }
	| { kind: 'record_payment'; chargeId: string | null }
	| { kind: 'apply_credit'; chargeId: string | null; receiptId: string | null }
	| { kind: 'refund'; receipt: BillingReceipt }
	| { kind: 'void'; recordKind: BillingRecordKind; recordId: string; subject: string }
	| { kind: 'correct_payment'; receipt: BillingReceipt }
	| { kind: 'confirm_coverage'; charge: BillingCharge }
	| { kind: 'adjust_paid_through' }
	| { kind: 'grant_free_access' }
	| { kind: 'extend_free_access'; grant: BillingFreeAccessGrant }
	| { kind: 'end_free_access'; grant: BillingFreeAccessGrant }
	| { kind: 'cancel_package_change'; agreement: BillingUpcomingAgreement }
	| { kind: 'apply_change_credit'; creditNoteId: string | null; chargeId: string | null };

// Package builder P8a/P8b: what `owner_package_change_preview` returns for one proposed move.
export type PackageChangeTiming = 'next_renewal' | 'now';
export type PackageChangeBlocker = { code: string; message: string };
export type PackageAllowanceSide = {
	state: 'numeric' | 'unlimited' | 'not_included';
	value: number | null;
};
/**
 * Package builder P11a/P11b: the offer frozen onto an agreement when it was claimed. Service periods that
 * start from `starts_on` up to the day before `ends_before` cost the intro price.
 */
export type AgreementOfferTerms = {
	offer_id: string;
	name: string;
	code: string | null;
	discount_kind: 'percent' | 'fixed';
	percent_off: number | null;
	amount_off_usd_cents: number | null;
	billing_interval: 'month' | 'year';
	periods: number;
	starts_on: string;
	ends_before: string;
	normal_price_usd_cents: number;
	intro_price_usd_cents: number;
};

export type PackageChangePreview = {
	organization_id: string;
	commercial_timezone: string;
	today: string;
	paid_through_date: string | null;
	timing: PackageChangeTiming;
	effective_date: string | null;
	effective_from: string | null;
	current: {
		agreement_id: string;
		edition_id: string;
		name: string;
		edition_number: number;
		package_slug: string;
		billing_interval: 'month' | 'year';
		agreed_price_usd_cents: number;
		offer_terms: AgreementOfferTerms | null;
	} | null;
	proposed: {
		edition_id: string;
		name: string;
		edition_number: number;
		package_slug: string;
		visibility: 'public' | 'private';
		billing_interval: 'month' | 'year';
		price_usd_cents: number | null;
	};
	capabilities: {
		capability_key: string;
		label: string;
		kind: 'core' | 'extra' | 'planned';
		current: boolean;
		proposed: boolean;
		exception: 'on' | 'off' | null;
	}[];
	allowances: {
		allowance_key: string;
		label: string;
		unit: string;
		resets_monthly: boolean;
		current: PackageAllowanceSide;
		proposed: PackageAllowanceSide;
		exception: (PackageAllowanceSide & { ends_at: string }) | null;
		in_use: number | null;
		excess: number;
	}[];
	over_limits: PackageChangePreview['allowances'];
	money: {
		credit_usd_cents: number;
		credit_from: string | null;
		credit_through: string | null;
		credit_source_charge_id: string | null;
		new_charge: {
			kind: 'period' | 'change';
			anchor_date: string;
			period_start: string;
			period_end: string;
			amount_usd_cents: number;
		} | null;
		credit_applied_usd_cents: number;
		replaced_charges: {
			id: string;
			period_start: string;
			period_end: string;
			amount_usd_cents: number;
		}[];
		next_charge: { period_start: string; period_end: string; amount_usd_cents: number } | null;
	};
	offer: {
		/** The offer the change would record: a new one, or the running one kept. */
		proposed: AgreementOfferTerms | null;
		kept: boolean;
		/** Whether the running offer can be kept: it lasts past the change and billing stays the same. */
		can_keep: boolean;
		/** Automatic offers this customer can take on the proposed package and billing. */
		available: ShownOffer[];
	};
	blockers: PackageChangeBlocker[];
};

export type TeamMember = {
	user_id: string;
	role: string;
	created_at: string;
	full_name: string | null;
	avatar_url: string | null;
	email: string | null;
	permission_overrides: { permission_key: string; override_state: string }[];
};
export type TeamResponse = {
	organization: { id: string; name: string };
	members: TeamMember[];
	has_administrator: boolean;
	error?: string;
};

export type HistoryEvent = {
	id: string;
	event_type: string;
	target_type: string;
	target_key: string | null;
	actor_email: string | null;
	occurred_at: string;
};
export type HistoryResponse = {
	organization: { id: string; name: string };
	events: HistoryEvent[];
	applicationId: string | null;
	error?: string;
};

export type OperationAttempt = {
	id: string;
	operation_type: string;
	target_kind: string;
	target_id: string;
	status: string;
	attempt_count: number;
	last_error: string | null;
	updated_at: string;
};
export type OperationListResponse = {
	operations: OperationAttempt[];
	error?: string;
};

export type MutationResponse = { error?: string };

// Package builder P8b: one temporary exception as `owner_organization_package_exceptions` lists it.
export type PackageException = {
	id: string;
	capability_key: string | null;
	capability_state: 'on' | 'off' | null;
	allowance_key: string | null;
	allowance_state: 'numeric' | 'unlimited' | 'not_included' | null;
	allowance_value: number | null;
	label: string;
	unit: string | null;
	reason: string;
	starts_at: string;
	ends_at: string;
	status: 'scheduled' | 'active' | 'ended' | 'cancelled';
	ended_early_at: string | null;
	end_reason: string | null;
	ended_by_email: string | null;
	actor_owner_email: string;
	created_at: string;
};
export type PackageExceptionCommandInput =
	| {
			action: 'add';
			target: 'capability' | 'allowance';
			key: string;
			capability_state: 'on' | 'off' | null;
			allowance_state: 'numeric' | 'unlimited' | 'not_included' | null;
			allowance_value: number | null;
			starts_at: string;
			ends_at: string;
			reason: string;
	  }
	| { action: 'end'; exception_id: string; reason: string };

// Package builder P8b: the Access tab's features and limits as `owner_organization_entitlements` reports
// them — the package's value, the exception running now, and what is in use for counted limits.
export type EntitlementCapability = {
	key: string;
	label: string;
	description: string;
	kind: 'core' | 'extra' | 'planned';
	in_package: boolean;
	exception: { state: 'on' | 'off'; ends_at: string } | null;
	effective: boolean;
};
export type EntitlementAllowance = {
	key: string;
	label: string;
	unit: string;
	resets_monthly: boolean;
	package: PackageAllowanceSide;
	exception: (PackageAllowanceSide & { ends_at: string }) | null;
	in_use: number | null;
};
export type OrganizationEntitlements = {
	capabilities: EntitlementCapability[];
	allowances: EntitlementAllowance[];
};
export type AccessExceptionsResponse = {
	exceptions: PackageException[];
	entitlements: OrganizationEntitlements;
	error?: string;
	field_errors?: Record<string, string>;
};
