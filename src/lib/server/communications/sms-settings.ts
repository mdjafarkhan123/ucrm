// Contractor-facing shaping for the Phone & SMS settings page (Stage 3C). These helpers turn the server-owned
// rows into the plain, safe shapes the contractor UI reads: a number the contractor may name or make default,
// the organization's SMS compliance preferences, and the read-only holds/opt-out picture. Provider-owned truth
// (buying or releasing a number, carrier submission) is never a field the contractor can write here.

export type SmsSenderRow = {
	id: string;
	phone_number: string;
	display_name: string | null;
	country_code: string | null;
	sender_type: string | null;
	lifecycle_state: string;
	capable_sms: boolean;
	capable_mms: boolean;
	capable_voice: boolean;
	allows_manual: boolean;
	allows_automated: boolean;
	registration_id: string | null;
	is_default_sender: boolean;
};

export type SmsComplianceRow = {
	opt_out_enabled: boolean;
	opt_out_text: string | null;
	sender_info_enabled: boolean;
	sender_info_text: string | null;
	periodic_reinsert_days: number;
	updated_at: string | null;
};

export type SmsHoldRow = {
	id: string;
	scope: string;
	reason: string;
	status: string;
	placed_at: string;
};

// A missing compliance row means the organization is on the system defaults. Keep these in one place so the GET
// (no row yet) and the table defaults never drift apart.
export const SMS_COMPLIANCE_DEFAULTS = {
	opt_out_enabled: true,
	opt_out_text: null as string | null,
	sender_info_enabled: true,
	sender_info_text: null as string | null,
	periodic_reinsert_days: 30
};

// Only a live, SMS-capable number can be the organization's default sending number. The same rule the
// set-default command enforces, exposed so the UI can explain why "Make default" is unavailable.
function canBeDefault(row: Pick<SmsSenderRow, 'lifecycle_state' | 'capable_sms'>) {
	return row.lifecycle_state === 'ready' && row.capable_sms;
}

export function safeSmsSender(row: SmsSenderRow) {
	return {
		id: row.id,
		phone_number: row.phone_number,
		display_name: row.display_name,
		country_code: row.country_code,
		sender_type: row.sender_type,
		lifecycle_state: row.lifecycle_state,
		capabilities: {
			sms: row.capable_sms,
			mms: row.capable_mms,
			voice: row.capable_voice
		},
		allows_manual: row.allows_manual,
		allows_automated: row.allows_automated,
		registration_id: row.registration_id,
		is_default_sender: row.is_default_sender,
		can_be_default: canBeDefault(row)
	};
}

export function safeSmsCompliance(row: SmsComplianceRow | null) {
	if (!row) {
		return { ...SMS_COMPLIANCE_DEFAULTS, updated_at: null, is_default: true };
	}
	return {
		opt_out_enabled: row.opt_out_enabled,
		opt_out_text: row.opt_out_text,
		sender_info_enabled: row.sender_info_enabled,
		sender_info_text: row.sender_info_text,
		periodic_reinsert_days: row.periodic_reinsert_days,
		updated_at: row.updated_at,
		is_default: false
	};
}

export function safeSmsHold(row: SmsHoldRow) {
	return {
		id: row.id,
		// A platform hold is not tied to this organization; a contractor can see it but never release it here.
		source: row.scope,
		reason: row.reason,
		status: row.status,
		placed_at: row.placed_at,
		// Every hold surfaced here is a request-to-owner recovery, never a direct contractor toggle.
		releasable_by_contractor: false
	};
}

// Stage 3D: the contractor-facing SMS usage page (balance, top-up requests, lean health and ledger). Reuses
// Stage 2C's money truth read-only; only a request/cancel action is contractor-writable here, never a balance,
// rate or hold -- those stay Jafar-only (src/lib/server/communications/sms-owner.ts).

export type SmsCreditAccountRow = {
	currency_code: string;
	settled_balance_minor: number;
	reserved_balance_minor: number;
} | null;

export type SmsBalance = {
	currency_code: string;
	settled_balance_minor: number;
	reserved_balance_minor: number;
	promotional_balance_minor: number;
	spendable_balance_minor: number;
};

export function safeSmsBalance(
	account: SmsCreditAccountRow,
	promotionalBalanceMinor: number,
	spendableBalanceMinor: number
): SmsBalance {
	return {
		currency_code: account?.currency_code ?? 'USD',
		settled_balance_minor: account?.settled_balance_minor ?? 0,
		reserved_balance_minor: account?.reserved_balance_minor ?? 0,
		promotional_balance_minor: promotionalBalanceMinor,
		spendable_balance_minor: spendableBalanceMinor
	};
}

export type SmsCreditTopupRequestRow = {
	id: string;
	requested_amount_minor: number;
	currency_code: string;
	offsite_reference: string | null;
	note: string | null;
	status: string;
	requested_at: string;
	decided_at: string | null;
	decision_reason: string | null;
	settled_amount_minor: number | null;
};

export function safeSmsCreditTopupRequest(row: SmsCreditTopupRequestRow) {
	return {
		id: row.id,
		requested_amount_minor: row.requested_amount_minor,
		currency_code: row.currency_code,
		offsite_reference: row.offsite_reference,
		note: row.note,
		status: row.status,
		requested_at: row.requested_at,
		decided_at: row.decided_at,
		decision_reason: row.decision_reason,
		settled_amount_minor: row.settled_amount_minor
	};
}

export type SmsLedgerEntryRow = {
	id: string;
	source_key: string;
	entry_kind: string;
	amount_minor: number;
	balance_after_minor: number;
	occurred_at: string;
	reason: string | null;
};

// Promotional credit never posts to this ledger (it is tracked, and expires, in its own table), so every row
// here is purchased money -- credited by a confirmed top-up, or debited by a charge, refund or adjustment.
export function safeSmsLedgerEntry(row: SmsLedgerEntryRow) {
	return {
		id: row.id,
		reference: row.source_key,
		entry_kind: row.entry_kind,
		bucket: 'purchased' as const,
		amount_minor: row.amount_minor,
		balance_after_minor: row.balance_after_minor,
		occurred_at: row.occurred_at,
		reason: row.reason
	};
}
