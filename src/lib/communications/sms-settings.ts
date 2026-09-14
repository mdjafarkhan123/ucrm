import { httpError } from '$lib/http-error';

// Client-side shapes and fetchers for the Phone numbers, Compliance & sender info, and Holds/opt-outs
// sections of the Phone & SMS settings page (Stage 3C-3). Mirrors the safe shapes returned by
// $lib/server/communications/sms-settings.ts; provider-owned actions (buy/release a number, carrier
// submission) are never fields this module writes.

export type SmsNumber = {
	id: string;
	phone_number: string;
	display_name: string | null;
	country_code: string | null;
	sender_type: string | null;
	lifecycle_state: string;
	capabilities: { sms: boolean; mms: boolean; voice: boolean };
	allows_manual: boolean;
	allows_automated: boolean;
	registration_id: string | null;
	is_default_sender: boolean;
	can_be_default: boolean;
};

export type SmsCompliance = {
	opt_out_enabled: boolean;
	opt_out_text: string | null;
	sender_info_enabled: boolean;
	sender_info_text: string | null;
	periodic_reinsert_days: number;
	updated_at: string | null;
	is_default: boolean;
};

export type SmsHold = {
	id: string;
	source: string;
	reason: string;
	status: string;
	placed_at: string;
	releasable_by_contractor: false;
};

export type SmsHoldsHome = {
	holds: SmsHold[];
	opt_outs: { total: number };
};

export class SmsSettingsWriteError extends Error {
	constructor(
		message: string,
		public readonly fieldErrors: Record<string, string> = {}
	) {
		super(message);
		this.name = 'SmsSettingsWriteError';
	}
}

const numbersUrl = '/api/settings/communications/sms/numbers';
const complianceUrl = '/api/settings/communications/sms/compliance';
const holdsUrl = '/api/settings/communications/sms/holds';

export const smsNumbersKey = ['settings', 'communications', 'sms', 'numbers'] as const;
export const smsComplianceKey = ['settings', 'communications', 'sms', 'compliance'] as const;
export const smsHoldsKey = ['settings', 'communications', 'sms', 'holds'] as const;

export async function fetchSmsNumbers(): Promise<{ numbers: SmsNumber[] }> {
	const response = await fetch(numbersUrl);
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw httpError(response, result.error ?? 'The numbers could not be loaded.');
	return result as { numbers: SmsNumber[] };
}

export async function renameSmsNumber(
	senderId: string,
	displayName: string
): Promise<{ number: SmsNumber }> {
	const response = await fetch(`${numbersUrl}/${senderId}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ action: 'rename', display_name: displayName })
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw new SmsSettingsWriteError(
			result.error ?? 'The number could not be renamed.',
			result.field_errors ?? {}
		);
	return result as { number: SmsNumber };
}

export async function setDefaultSmsNumber(senderId: string): Promise<{ number: SmsNumber }> {
	const response = await fetch(`${numbersUrl}/${senderId}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ action: 'set_default' })
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw new SmsSettingsWriteError(result.error ?? 'That number could not be made the default.');
	return result as { number: SmsNumber };
}

export async function fetchSmsCompliance(): Promise<{ compliance: SmsCompliance }> {
	const response = await fetch(complianceUrl);
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'The compliance settings could not be loaded.');
	return result as { compliance: SmsCompliance };
}

export async function saveSmsCompliance(body: {
	opt_out_enabled: boolean;
	opt_out_text: string | null;
	sender_info_enabled: boolean;
	sender_info_text: string | null;
	periodic_reinsert_days: number;
}): Promise<{ compliance: SmsCompliance }> {
	const response = await fetch(complianceUrl, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw new SmsSettingsWriteError(
			result.error ?? 'The compliance settings could not be saved.',
			result.field_errors ?? {}
		);
	return result as { compliance: SmsCompliance };
}

export async function fetchSmsHolds(): Promise<SmsHoldsHome> {
	const response = await fetch(holdsUrl);
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw httpError(response, result.error ?? 'The holds could not be loaded.');
	return result as SmsHoldsHome;
}
