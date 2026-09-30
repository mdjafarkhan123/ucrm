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
export type BillingApplication = {
	id: string;
	receipt_id: string;
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
		offer_terms: unknown;
		effective_from: string;
	} | null;
	upcoming_agreements: {
		id: string;
		edition_name: string;
		edition_number: number;
		billing_interval: 'month' | 'year';
		agreed_price_usd_cents: number;
		effective_from: string;
	}[];
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
	| { action: 'end_free_access'; grant_id: string; reason: string };
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
	| { kind: 'end_free_access'; grant: BillingFreeAccessGrant };

export type TeamMember = {
	user_id: string;
	role: string;
	created_at: string;
	full_name: string | null;
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
