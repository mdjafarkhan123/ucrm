import {
	createTwilioCountryCatalogClient,
	type AddressRequirement,
	type AvailableNumber,
	type CatalogCountry,
	type CountryMessagePrices,
	type CountryNumberPrices,
	type NumberRegulation,
	type NumberSearchInput,
	type NumberType,
	type RegulationQuery,
	type TwilioCountryCatalogClient
} from './twilio-country-catalog';

// Global texting country catalog (Stage 10 Part 1): what each country offers, read live from Twilio behind a short
// in-process cache. The country list is every country where Twilio has numbers in stock; the app blocks no region
// (Jafar, 2026-10-22: who can text is decided by who he sells subscriptions to).
//
// Cached answers change slowly (countries, paperwork, prices), so a few minutes stale is harmless and spares Twilio
// a call per screen open. A number search is never cached: stock changes by the minute and the next step may be a
// purchase. Failures are never cached, so an outage clears as soon as Twilio recovers. Concurrent callers for the
// same key share one in-flight request.

const DEFAULT_TTL_MS = 10 * 60 * 1000;
const MAX_ENTRIES = 1000;

export type NumberTypeOption = {
	numberType: NumberType;
	// Whether any number of this type in stock now can text, send pictures, or take calls. Voice-only stock is
	// never texting-ready.
	canText: boolean;
	canSendPictures: boolean;
	canCall: boolean;
	// The address rule of the first texting number found; the rule shown at purchase stays the source of truth.
	addressRequirement: AddressRequirement | null;
};

export type SmsCountryCatalog = {
	listCountries(): Promise<CatalogCountry[]>;
	/** Each in-stock number type for a country and what it can do. Empty when the country has no stock. */
	listNumberTypeOptions(countryCode: string): Promise<NumberTypeOption[]>;
	/** Live stock, never cached. */
	searchNumbers(input: NumberSearchInput): Promise<AvailableNumber[]>;
	getRegulation(query: RegulationQuery): Promise<NumberRegulation | null>;
	getNumberPrices(countryCode: string): Promise<CountryNumberPrices | null>;
	getMessagePrices(countryCode: string): Promise<CountryMessagePrices | null>;
	/** Drop every cached answer, e.g. after Jafar changes Twilio account pricing. */
	clear(): void;
};

export type SmsCountryCatalogDeps = {
	client: TwilioCountryCatalogClient;
	ttlMs?: number;
	now?: () => number;
};

export function createSmsCountryCatalog({
	client,
	ttlMs = DEFAULT_TTL_MS,
	now = Date.now
}: SmsCountryCatalogDeps): SmsCountryCatalog {
	const cache = new Map<string, { expiresAt: number; value: Promise<unknown> }>();

	function cached<T>(key: string, load: () => Promise<T>): Promise<T> {
		const hit = cache.get(key);
		if (hit && hit.expiresAt > now()) return hit.value as Promise<T>;
		cache.delete(key);

		const value = load();
		cache.set(key, { expiresAt: now() + ttlMs, value });
		value.catch(() => {
			if (cache.get(key)?.value === value) cache.delete(key);
		});
		// Map keeps insertion order, so the first key is the oldest entry.
		while (cache.size > MAX_ENTRIES) {
			const oldest = cache.keys().next().value;
			if (oldest === undefined) break;
			cache.delete(oldest);
		}
		return value;
	}

	const catalog: SmsCountryCatalog = {
		listCountries: () => cached('countries', () => client.listCountries()),

		listNumberTypeOptions: (countryCode) =>
			cached(`options:${countryCode}`, async () => {
				const country = (await catalog.listCountries()).find(
					(candidate) => candidate.countryCode === countryCode
				);
				if (!country) return [];
				return Promise.all(
					country.numberTypes.map((numberType) => probeNumberType(client, countryCode, numberType))
				);
			}),

		searchNumbers: (input) => client.searchNumbers(input),

		getRegulation: (query) =>
			cached(`regulation:${query.countryCode}:${query.numberType}:${query.endUserType}`, () =>
				client.getRegulation(query)
			),

		getNumberPrices: (countryCode) =>
			cached(`number-prices:${countryCode}`, () => client.getNumberPrices(countryCode)),

		getMessagePrices: (countryCode) =>
			cached(`message-prices:${countryCode}`, () => client.getMessagePrices(countryCode)),

		clear: () => cache.clear()
	};

	return catalog;
}

// Ask Twilio for one texting-capable number of this type, then only check pictures or calls separately when that
// number did not already show them. Usually one or two small requests per type.
async function probeNumberType(
	client: TwilioCountryCatalogClient,
	countryCode: string,
	numberType: NumberType
): Promise<NumberTypeOption> {
	const probe = (filter: Pick<NumberSearchInput, 'sms' | 'mms' | 'voice'>) =>
		client.searchNumbers({ countryCode, numberType, ...filter, limit: 1 }).then((rows) => rows[0]);

	const texting = await probe({ sms: true });
	const [picture, calling] = await Promise.all([
		texting?.capabilities.mms ? texting : probe({ mms: true }),
		texting?.capabilities.voice ? texting : probe({ voice: true })
	]);

	return {
		numberType,
		canText: Boolean(texting),
		canSendPictures: Boolean(picture?.capabilities.mms),
		canCall: Boolean(calling?.capabilities.voice),
		addressRequirement: texting?.addressRequirement ?? null
	};
}

let sharedCatalog: SmsCountryCatalog | null = null;

/** The process-wide catalog over the live Twilio client. Throws if Twilio credentials are not configured. */
export function getSmsCountryCatalog(): SmsCountryCatalog {
	sharedCatalog ??= createSmsCountryCatalog({ client: createTwilioCountryCatalogClient() });
	return sharedCatalog;
}
