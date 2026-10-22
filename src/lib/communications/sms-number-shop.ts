import { httpError } from '$lib/http-error';

// Client shapes and fetchers for the Add number pop-up (Stage 10 Part 2). Mirrors
// $lib/server/communications/sms-number-shop.ts and the number-orders route.

export type NumberType = 'local' | 'mobile' | 'national' | 'toll_free';
export type NumberKindNeed = 'none' | 'register_after' | 'paperwork_first';
export type Abilities = { sms: boolean; mms: boolean; voice: boolean };

export type NumberCountry = { country_code: string; name: string };

export type NumberKind = {
	number_type: NumberType;
	can_text: boolean;
	can_send_pictures: boolean;
	can_call: boolean;
	monthly_minor: number | null;
	setup_minor: number | null;
	currency_code: string;
	needs: NumberKindNeed;
};

export type NumberKinds = {
	country_code: string;
	kinds: NumberKind[];
	balance_minor: number;
	currency_code: string;
};

export type ShopNumber = {
	phone_number: string;
	friendly_name: string;
	locality: string | null;
	region: string | null;
	capabilities: Abilities;
	address_requirement: string;
};

export type NumberOrderState = 'reserved' | 'purchasing' | 'purchased' | 'completed' | 'failed';

export type NumberOrder = {
	id: string;
	state: NumberOrderState;
	phone_number: string;
	country_code: string;
	number_type: NumberType;
	locality: string | null;
	region: string | null;
	capabilities: Abilities;
	monthly_minor: number;
	setup_minor: number;
	charge_minor: number;
	currency_code: string;
	sender_identity_id: string | null;
	failure_code: string | null;
	failure_message: string | null;
};

export type NumberSearch = {
	country: string;
	type: NumberType;
	contains: string;
	mms: boolean;
	voice: boolean;
};

const base = '/api/settings/communications/sms';

export const numberCountriesKey = [
	'settings',
	'communications',
	'sms',
	'number-countries'
] as const;
export const numberKindsKey = (country: string) =>
	['settings', 'communications', 'sms', 'number-kinds', country] as const;
export const shopNumbersKey = (search: NumberSearch) =>
	['settings', 'communications', 'sms', 'shop-numbers', search] as const;

/** A load that failed because the phone company did not answer, as distinct from our own server failing. */
export class ProviderUnavailableError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'ProviderUnavailableError';
	}
}

async function read<T>(response: Response, fallback: string): Promise<T> {
	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		if (result.code === 'provider_unavailable') throw new ProviderUnavailableError(result.error);
		throw httpError(response, result.error ?? fallback);
	}
	return result as T;
}

/** The countries with numbers in stock, and the business's own country when it is one of them. */
export async function fetchNumberCountries(): Promise<{
	countries: NumberCountry[];
	home_country: string | null;
}> {
	const response = await fetch(`${base}/number-countries`);
	return read(response, 'The countries could not be loaded.');
}

export async function fetchNumberKinds(country: string): Promise<NumberKinds> {
	const response = await fetch(`${base}/number-countries/${encodeURIComponent(country)}`);
	return read<NumberKinds>(response, 'The kinds of number could not be loaded.');
}

export async function fetchShopNumbers(search: NumberSearch): Promise<ShopNumber[]> {
	const params = new URLSearchParams({ country: search.country, type: search.type });
	if (search.contains) params.set('contains', search.contains);
	if (search.mms) params.set('mms', 'true');
	if (search.voice) params.set('voice', 'true');
	const response = await fetch(`${base}/available-numbers?${params}`);
	return (await read<{ numbers: ShopNumber[] }>(response, 'The numbers could not be loaded.'))
		.numbers;
}

export type BuyResult =
	| { kind: 'done'; order: NumberOrder }
	| { kind: 'checking'; order: NumberOrder | null; message: string }
	| { kind: 'refused'; code: string | null; message: string };

/** Buy, or continue buying, the number for this key. A 202 means "still checking with Twilio": ask again. */
export async function buyNumber(body: {
	idempotency_key: string;
	phone_number: string;
	country_code: string;
	number_type: NumberType;
}): Promise<BuyResult> {
	let response: Response;
	try {
		response = await fetch(`${base}/number-orders`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		});
	} catch {
		// The connection dropped: the order may or may not have reached Twilio. The same key finds out safely.
		return { kind: 'checking', order: null, message: '' };
	}
	const result = await response.json().catch(() => ({}));
	if (response.status === 202) {
		return { kind: 'checking', order: result.order ?? null, message: result.error ?? '' };
	}
	if (response.ok) return { kind: 'done', order: result.order as NumberOrder };
	return {
		kind: 'refused',
		code: result.code ?? null,
		message: result.error ?? 'The number could not be bought.'
	};
}

const TYPE_LABELS: Record<NumberType, string> = {
	local: 'Local',
	mobile: 'Mobile',
	national: 'National',
	toll_free: 'Toll-free'
};

export function numberTypeLabel(type: NumberType): string {
	return TYPE_LABELS[type];
}

export function formatMinor(minor: number, currency: string): string {
	return new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(minor / 100);
}

/** "+1 (512) 555-0142" for North American numbers; other countries keep their international form. */
export function formatPhone(e164: string): string {
	const match = /^\+1(\d{3})(\d{3})(\d{4})$/.exec(e164);
	return match ? `+1 (${match[1]}) ${match[2]}-${match[3]}` : e164;
}
