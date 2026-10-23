import { dayLabel } from '$lib/collaboration/format';
import { jafarOrganizationSmsDestinationsKey } from '$lib/jafar/query-keys';

// Stage 10 Part 5b: Uplift's Texting setup page and a business's countries card (`concept.pen` board `v6Jtu`).

export type CountryPrice = {
	segment: { rate: number; cost: number | null; currency: string } | null;
	mms: { rate: number; cost: number | null; currency: string } | null;
};

export type DestinationEvent = {
	kind: 'requested' | 'switched_on' | 'closed' | 'turned_off';
	at: string;
	who: string | null;
	note: string | null;
};

export type TextingTask = {
	id: string;
	organization_id: string;
	organization_name: string;
	country: string;
	is_home: boolean;
	requested_at: string;
	requested_by: string | null;
	account_sid: string | null;
	price: CountryPrice;
	history: DestinationEvent[];
};

export type TextingSetupQueue = {
	summary: {
		to_do: number;
		oldest_at: string | null;
		waiting_on_twilio: number;
		countries_live: number;
		businesses_live: number;
		countries_without_price: { country: string; businesses: number }[];
	};
	/** Tasks someone switched on or closed in the last day, and who. */
	recently_finished: { id: string; kind: string; at: string; who: string | null }[];
	tasks: TextingTask[];
};

export type BusinessDestination = {
	id: string;
	country: string;
	status: 'setting_up' | 'ready' | 'off';
	is_home: boolean;
	requested_at: string;
	ready_at: string | null;
	off_at: string | null;
	off_reason: string | null;
	price: CountryPrice;
	history: DestinationEvent[];
};

export type BusinessDestinations = {
	account_sid: string | null;
	destinations: BusinessDestination[];
};

/** Who finished a task first, when a teammate beat this person to it. */
export type AlreadyFinished = { kind: string; at: string; who: string | null };

export const textingSetupKey = ['jafar', 'texting-setup'] as const;
export const organizationDestinationsKey = jafarOrganizationSmsDestinationsKey;

async function readJson<T>(response: Response, fallback: string): Promise<T> {
	const body = await response.json().catch(() => ({}));
	if (!response.ok) throw new Error(body.error ?? fallback);
	return body as T;
}

export async function fetchTextingSetup(): Promise<TextingSetupQueue> {
	return readJson(await fetch('/api/jafar/texting-setup'), 'The to-do list could not be loaded.');
}

/** "$0.09", "$0.0079": a text price keeps the digits it was set with, at least two. */
export function textPrice(amount: number): string {
	const digits = Math.min(Math.max(2, (String(amount).split('.')[1] ?? '').length), 4);
	return `$${amount.toFixed(digits)}`;
}

/** "42%": what Uplift keeps from a price after Twilio's cost. */
export function margin(rate: number, cost: number): string {
	return `${Math.round(((rate - cost) / rate) * 100)}%`;
}

/** "today", "yesterday", "Oct 12": when something happened, in a line of other words. */
export function whenAsked(value: string): string {
	const label = dayLabel(value);
	if (label === 'Today' || label === 'Yesterday') return label.toLowerCase();
	return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(
		new Date(value)
	);
}

/** "Yesterday 4:12 pm", "Oct 20": a history row's time. */
export function historyTime(value: string): string {
	const date = new Date(value);
	const label = dayLabel(value);
	const time = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(date);
	if (label === 'Today' || label === 'Yesterday') return `${label} ${time}`;
	return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(date);
}

/** A twilio account id cut down for reading: "AC…4f2e". */
export function shortSid(sid: string): string {
	return `${sid.slice(0, 2)}…${sid.slice(-4)}`;
}

/** Twilio's SMS Geo permissions page. Twilio switches accounts by hand, so the id is copied beside it. */
export const TWILIO_GEO_PERMISSIONS_URL =
	'https://console.twilio.com/us1/develop/sms/settings/geo-permissions';

/**
 * What a business's country row says. Ready needs both the Twilio permission and a price, so a country that
 * is switched on but has no price yet still reads Setting up.
 */
export function destinationStatus(destination: BusinessDestination) {
	if (destination.status === 'off') return { label: 'Off', tone: 'inactive' as const };
	if (destination.status === 'ready' && destination.price.segment) {
		return { label: 'Ready', tone: 'success' as const };
	}
	return { label: 'Setting up', tone: 'warning' as const };
}

/** Twilio's Subaccounts list. Twilio has no link to one account's page, so the card copies the id beside it. */
export const TWILIO_SUBACCOUNTS_URL =
	'https://console.twilio.com/us1/account/manage-account/subaccounts';
