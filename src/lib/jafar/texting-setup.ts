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
	/** Languages beyond English whose opt-out words the business still needs before this country (Part 5d). */
	opt_out_missing: string[];
};

/** Add a language's opt-out words to a business's Twilio messaging service (Part 5d). */
export type OptOutTask = {
	/** `opt-out:<organization>:<language>`. */
	id: string;
	organization_id: string;
	organization_name: string;
	language: string;
	/** The asked countries that need it. */
	countries: string[];
	requested_at: string;
	messaging_service_sid: string | null;
};

/** A number that couldn't renew (Part 7). Nothing to do unless the business asks; it closes by itself. */
export type UnpaidNumberTask = {
	/** `unpaid:<sender>`. */
	id: string;
	sender_id: string;
	organization_id: string;
	organization_name: string;
	owner_name: string | null;
	name: string;
	phone_number: string;
	country: string;
	number_type: string;
	/** The renewal day it couldn't pay, so it sorts with the other tasks. */
	requested_at: string;
	grace_ends_at: string;
	amount_minor: number;
	balance_minor: number;
	currency: string;
	history: { kind: 'renewed' | 'failed' | 'warned'; at: string; text: string }[];
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
	opt_out_tasks: OptOutTask[];
	unpaid_number_tasks: UnpaidNumberTask[];
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
	/** Languages beyond English whose opt-out words Uplift added to the business's messaging service. */
	opt_out_languages: { language: string; at: string; who: string | null }[];
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

/** Something Uplift sent to Twilio for a business and is waiting to hear back on (Waiting on Twilio tab). */
export type WaitingItem = {
	kind: 'registration' | 'paperwork' | 'tollfree';
	id: string;
	organization_id: string;
	organization_name: string;
	/** Twilio answered no in the last week; the business was told what to fix. */
	turned_down: boolean;
	sent_at: string | null;
	decided_at: string | null;
	/** Paperwork: "GB:mobile". Toll-free: the number. */
	detail: string | null;
};

export type WaitingOnTwilio = { items: WaitingItem[]; last_checked_at: string | null };

export const waitingOnTwilioKey = [...textingSetupKey, 'waiting'] as const;

export async function fetchWaitingOnTwilio(): Promise<WaitingOnTwilio> {
	return readJson(
		await fetch('/api/jafar/texting-setup/waiting'),
		'The Waiting on Twilio list could not be loaded.'
	);
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
	const time = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(
		date
	);
	if (label === 'Today' || label === 'Yesterday') return `${label} ${time}`;
	return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(date);
}

/** A twilio account id cut down for reading: "AC…4f2e". */
export function shortSid(sid: string): string {
	return `${sid.slice(0, 2)}…${sid.slice(-4)}`;
}

/** Twilio's Messaging Services list, where each service's Opt-Out tab takes the language words. */
export const TWILIO_MESSAGING_SERVICES_URL = 'https://console.twilio.com/us1/develop/sms/services';

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

// Stage 10 Part 6: the Countries & prices tab (cards `R6mF2`, `dc8G7`). One price list for every business.

export type PriceListRow = {
	country: string;
	/** The number kind a business buys there: local, mobile or national. */
	number_type: string;
	toll_free: boolean;
	/** False once Uplift stopped offering the country (status Off). */
	offered: boolean;
	twilio: {
		segment: {
			cost: number;
			previous: number | null;
			changed_at: string | null;
			checked_at: string;
		} | null;
		number_month: { cost: number; checked_at: string } | null;
	};
	price: CountryPrice;
	/** When a segment price was last saved, so a Twilio move after it still needs reviewing. */
	segment_set_at: string | null;
	number: { monthly: number; setup: number } | null;
	/** A segment price starting later, shown on its row until that day. */
	later: { segment: number; from: string } | null;
	using: number;
	asked: number;
};

export type PriceList = { last_checked_at: string | null; countries: PriceListRow[] };

export const priceListKey = [...textingSetupKey, 'prices'] as const;

export async function fetchPriceList(): Promise<PriceList> {
	return readJson(
		await fetch('/api/jafar/texting-setup/prices'),
		'The price list could not be loaded.'
	);
}

/** Twilio sends picture texts only to these countries; elsewhere a picture arrives as a link or not at all. */
export const PICTURE_COUNTRIES = ['US', 'CA'] as const;

export function picturesOffered(row: Pick<PriceListRow, 'country' | 'price'>): boolean {
	return Boolean(row.price.mms) || (PICTURE_COUNTRIES as readonly string[]).includes(row.country);
}

/** Twilio raised its text cost after the price was last set, so the margin shown has fallen. */
export function priceMoved(row: PriceListRow): boolean {
	const segment = row.twilio.segment;
	if (!segment?.changed_at || segment.previous === null || segment.cost <= segment.previous)
		return false;
	return !row.segment_set_at || segment.changed_at > row.segment_set_at;
}

export function priceStatus(row: PriceListRow) {
	if (!row.offered) return { label: 'Off', tone: 'inactive' as const };
	if (!row.price.segment) return { label: 'No price', tone: 'warning' as const };
	return { label: 'Live', tone: 'success' as const };
}

/** "Local and toll-free", "Mobile numbers". */
export function numberKindLabel(row: Pick<PriceListRow, 'number_type' | 'toll_free'>): string {
	const kind =
		{ local: 'Local', mobile: 'Mobile', national: 'National' }[row.number_type] ?? 'Local';
	return row.toll_free ? `${kind} and toll-free` : `${kind} numbers`;
}

/** "$2.00", "$9.00 + $3.00 setup". */
export function numberPrice(number: PriceListRow['number']): string | null {
	if (!number) return null;
	const monthly = `$${number.monthly.toFixed(2)}`;
	return number.setup > 0 ? `${monthly} + $${number.setup.toFixed(2)} setup` : monthly;
}
