import { httpError } from '$lib/http-error';

// Client-side shapes and fetchers for the SMS usage settings page (Stage 3D): balance, this month's usage
// summary, lean messaging health, the credit ledger and the contractor's own top-up requests. Mirrors the
// safe shapes returned by $lib/server/communications/sms-settings.ts. Only requesting or cancelling a top-up
// is contractor-writable here -- balance, rates and holds stay Jafar-only.

export type SmsUsageBalance = {
	currency_code: string;
	settled_balance_minor: number;
	reserved_balance_minor: number;
	promotional_balance_minor: number;
	spendable_balance_minor: number;
};

export type SmsUsageSummary = {
	period_start: string;
	period_end: string;
	retail_charge_minor: number;
	messages: number;
	segments: number;
	adjustments_count: number;
	adjustments_amount_minor: number;
};

export type SmsMessagingHealth = {
	period_days: number;
	sent: number;
	delivered: number;
	failed: number;
	received: number;
	opt_out_rate: number | null;
};

export type SmsAvailability = {
	state: 'available' | 'paused' | 'zero_balance';
	reason: string | null;
};

export type SmsUsageHome = {
	balance: SmsUsageBalance;
	availability: SmsAvailability;
	usage_summary: SmsUsageSummary;
	messaging_health: SmsMessagingHealth;
};

export type SmsCreditTopupStatus = 'awaiting_confirmation' | 'confirmed' | 'rejected' | 'cancelled';

export type SmsCreditTopupRequest = {
	id: string;
	requested_amount_minor: number;
	currency_code: string;
	offsite_reference: string | null;
	note: string | null;
	status: SmsCreditTopupStatus;
	requested_at: string;
	decided_at: string | null;
	decision_reason: string | null;
	settled_amount_minor: number | null;
};

export type SmsLedgerEntry = {
	id: string;
	reference: string;
	entry_kind: 'credit' | 'charge' | 'refund' | 'adjustment';
	bucket: 'purchased';
	amount_minor: number;
	balance_after_minor: number;
	occurred_at: string;
	reason: string | null;
};

export type SmsLedgerPage = {
	entries: SmsLedgerEntry[];
	next_cursor: string | null;
};

export class SmsUsageWriteError extends Error {
	constructor(
		message: string,
		public readonly fieldErrors: Record<string, string> = {}
	) {
		super(message);
		this.name = 'SmsUsageWriteError';
	}
}

const usageUrl = '/api/settings/communications/sms/usage';
const creditTopupsUrl = '/api/settings/communications/sms/credit-topups';
const ledgerUrl = '/api/settings/communications/sms/ledger';

export const smsUsageKey = ['settings', 'communications', 'sms', 'usage'] as const;
export const smsCreditTopupsKey = ['settings', 'communications', 'sms', 'credit-topups'] as const;
export const smsLedgerKey = (filters: { entry_kind?: string } = {}) =>
	['settings', 'communications', 'sms', 'ledger', filters] as const;

// Plain English for the contractor's own request history. Jafar's own view keeps its literal wording
// ("Awaiting confirmation" / "Rejected"); this is the contractor-facing set from the product blueprint.
export const smsCreditTopupStatusLabel: Record<SmsCreditTopupStatus, string> = {
	awaiting_confirmation: 'Pending',
	confirmed: 'Confirmed',
	rejected: 'Declined',
	cancelled: 'Cancelled'
};

export const smsCreditTopupStatusTone: Record<
	SmsCreditTopupStatus,
	'success' | 'warning' | 'critical' | 'inactive'
> = {
	awaiting_confirmation: 'warning',
	confirmed: 'success',
	rejected: 'critical',
	cancelled: 'inactive'
};

export const smsLedgerEntryKindLabel: Record<SmsLedgerEntry['entry_kind'], string> = {
	credit: 'Top-up',
	charge: 'Message charge',
	refund: 'Refund',
	adjustment: 'Adjustment'
};

export const smsAvailabilityLabel: Record<SmsAvailability['state'], string> = {
	available: 'Available',
	paused: 'Paused',
	zero_balance: 'Zero balance'
};

export const smsAvailabilityTone: Record<
	SmsAvailability['state'],
	'success' | 'warning' | 'critical'
> = {
	available: 'success',
	paused: 'warning',
	zero_balance: 'critical'
};

export function formatSmsMoney(minor: number, currency: string) {
	return `${minor < 0 ? '-' : ''}$${(Math.abs(minor) / 100).toFixed(2)} ${currency}`;
}

export async function fetchSmsUsage(): Promise<SmsUsageHome> {
	const response = await fetch(usageUrl);
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw httpError(response, result.error ?? 'The SMS usage could not be loaded.');
	return result as SmsUsageHome;
}

export async function fetchSmsCreditTopups(): Promise<{ requests: SmsCreditTopupRequest[] }> {
	const response = await fetch(creditTopupsUrl);
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'The top-up requests could not be loaded.');
	return result as { requests: SmsCreditTopupRequest[] };
}

export async function requestSmsCreditTopup(body: {
	requested_amount_minor: number;
	offsite_reference: string | null;
	note: string | null;
}): Promise<{ request: SmsCreditTopupRequest }> {
	const response = await fetch(creditTopupsUrl, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw new SmsUsageWriteError(
			result.error ?? 'The top-up request could not be submitted.',
			result.field_errors ?? {}
		);
	return result as { request: SmsCreditTopupRequest };
}

export async function cancelSmsCreditTopup(
	requestId: string
): Promise<{ request: SmsCreditTopupRequest }> {
	const response = await fetch(`${creditTopupsUrl}/${requestId}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ action: 'cancel' })
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw new SmsUsageWriteError(result.error ?? 'The top-up request could not be cancelled.');
	return result as { request: SmsCreditTopupRequest };
}

export async function fetchSmsLedger(
	cursor: string | undefined,
	filters: { entry_kind?: string } = {}
): Promise<SmsLedgerPage> {
	const params = new URLSearchParams();
	if (cursor) params.set('cursor', cursor);
	if (filters.entry_kind) params.set('entry_kind', filters.entry_kind);
	const query = params.toString();
	const response = await fetch(query ? `${ledgerUrl}?${query}` : ledgerUrl);
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw httpError(response, result.error ?? 'The ledger could not be loaded.');
	return result as SmsLedgerPage;
}
