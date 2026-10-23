import { getCountryCallingCode, type CountryCode } from 'libphonenumber-js';
import { httpError } from '$lib/http-error';
import { countryDisplayName } from '$lib/settings/country-names';
import { formatPhone } from '$lib/communications/sms-number-shop';
import type { ReadinessNumber } from '$lib/communications/number-readiness';

// The countries a business can text (Stage 10 Part 5c, `concept.pen` board `xGLYB`). Uplift switches each
// country on in Twilio by hand, so a business asks for one and sees Setting up until it is done. Pure helpers
// here decide which of its numbers can text a country and how a price reads; the pop-up only draws them.

export type DestinationStatus = 'setting_up' | 'ready' | 'off';
export type Destination = { country: string; status: DestinationStatus; is_home: boolean };
export type CountryPrice = {
	country: string;
	currency: string;
	/** One text segment (up to 160 letters), in major units. */
	segment: number | null;
	/** One picture text, where pictures go through. */
	mms: number | null;
	/** Renting a number there, a month. */
	number_monthly: number | null;
};
export type TextingCountries = {
	destinations: Destination[];
	/** Countries Uplift doesn't offer; the list leaves them out. */
	not_offered: string[];
	prices: CountryPrice[];
};

export const textingCountriesKey = ['settings', 'communications', 'sms', 'destinations'] as const;

export async function fetchTextingCountries(): Promise<TextingCountries> {
	const response = await fetch('/api/settings/communications/sms/destinations');
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw httpError(response, result.error ?? 'The countries could not be loaded.');
	return result as TextingCountries;
}

export async function requestTextingCountry(countryCode: string): Promise<Destination> {
	const response = await fetch('/api/settings/communications/sms/destinations', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ country_code: countryCode })
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw httpError(
			response,
			result.error ?? 'We couldn’t send your request. Check your connection and try again.'
		);
	}
	return result as Destination;
}

const NORTH_AMERICA = ['US', 'CA'];

/** A +1 number texts both the US and Canada; every other number texts its own country. */
export function numberReach(countryCode: string): string[] {
	return NORTH_AMERICA.includes(countryCode) ? NORTH_AMERICA : [countryCode];
}

/** "+61", or empty for a code the phone library doesn't know. */
export function diallingCode(countryCode: string): string {
	try {
		return `+${getCountryCallingCode(countryCode as CountryCode)}`;
	} catch {
		return '';
	}
}

/** "$0.08"; tiny rates keep their extra digits ("$0.0083") so a price never rounds to nothing. */
export function formatRate(amount: number, currency: string): string {
	return new Intl.NumberFormat('en-US', {
		style: 'currency',
		currency,
		minimumFractionDigits: 2,
		maximumFractionDigits: 4
	}).format(amount);
}

export type NumberBand =
	| { tone: 'success'; title: string; line: string }
	| { tone: 'warning'; title: string; line: string };

/** Which number would text customers in a country: one the business has, or a new one it needs. */
export function numberBand(numbers: ReadinessNumber[], countryCode: string): NumberBand {
	const country = countryDisplayName(countryCode);
	const reaching = numbers.filter((number) =>
		numberReach(number.country_code).includes(countryCode)
	);
	if (reaching.length > 0) {
		const number = reaching.find((entry) => entry.is_default_sender) ?? reaching[0];
		const name = number.display_name?.trim() || `${formatPhone(number.phone_number)} number`;
		const crossing = number.country_code !== countryCode;
		return {
			tone: 'success',
			title: `Your ${name} can text ${country}`,
			line: crossing ? '+1 numbers text the US and Canada. Nothing to buy.' : 'Nothing to buy.'
		};
	}
	const owned = [...new Set(numbers.map((number) => number.country_code))].map(countryDisplayName);
	return {
		tone: 'warning',
		title: `You need a number in ${country}`,
		line: owned.length
			? `Your ${listed(owned)} ${numbers.length === 1 ? 'number' : 'numbers'} can’t text ${country}. Add one here once it’s switched on.`
			: 'Add one here once it’s switched on.'
	};
}

function listed(names: string[]): string {
	if (names.length < 2) return names.join('');
	return `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}`;
}

export const DESTINATION_LABELS: Record<Exclude<DestinationStatus, 'off'>, string> = {
	ready: 'Ready',
	setting_up: 'Setting up'
};
