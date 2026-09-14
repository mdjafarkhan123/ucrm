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
