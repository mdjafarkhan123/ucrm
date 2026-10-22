import { getTwilioPlatformEnv, type TwilioPlatformEnv } from './twilio';

// Twilio country catalog adapter (Stage 10 Part 1). The only module that reads what Twilio offers per country:
// which number types are in stock and what each can do, the paperwork a number needs, and the account's own
// number and message prices. Read-only -- nothing here buys, registers, or spends. Verified against Twilio's
// docs and live read-only calls (2026-10-22), not guessed:
//   - Inventory:   GET https://api.twilio.com/2010-04-01/Accounts/{sid}/AvailablePhoneNumbers[/{CC}[/{Type}]].json
//   - Paperwork:   GET https://numbers.twilio.com/v2/RegulatoryCompliance/Regulations?IncludeConstraints=true
//   - Prices:      GET https://pricing.twilio.com/v1/PhoneNumbers/Countries/{CC}
//                  GET https://pricing.twilio.com/v1/Messaging/Countries/{CC}
//
// Twilio warns against hardcoding regulatory-bundle requirements, so they are always read live. The three APIs
// spell number types differently (`toll_free`, `toll-free`, `toll free`); this adapter normalizes them to one
// vocabulary. Live capability keys arrive as `SMS`/`MMS`/`voice` although the reference documents lowercase, so
// both spellings are read.
//
// Authenticated with the platform's main-account API key (TWILIO_PROVISIONING_KEY_SID/SECRET). Inventory is read
// on the platform account; subaccounts buy from the same pool. Prices are the account's `current_price`, which
// already reflects any account-specific discount.

const COUNTRY_CODE = /^[A-Z]{2}$/;
const SEARCH_CONTAINS = /^[0-9A-Za-z*]{1,16}$/;
const AREA_CODE = /^[0-9]{1,6}$/;

const TWILIO_API_BASE = 'https://api.twilio.com';
const NUMBERS_BASE = 'https://numbers.twilio.com';
const PRICING_BASE = 'https://pricing.twilio.com';

const PROVIDER_TIMEOUT_MS = 15_000;
// A hard safety valve against an unbounded page-follow loop; real lists fit in one page.
const MAX_PAGES = 5;
const MAX_SEARCH_RESULTS = 50;

export const NUMBER_TYPES = ['local', 'mobile', 'national', 'toll_free'] as const;
export type NumberType = (typeof NUMBER_TYPES)[number];
// Message prices are also quoted for short codes, which are not bought through number search.
export type MessagePriceSenderType = NumberType | 'short_code';
export type EndUserType = 'business' | 'individual';
export type AddressRequirement = 'none' | 'any' | 'local' | 'foreign';

const SEARCH_PATH: Record<NumberType, string> = {
	local: 'Local',
	mobile: 'Mobile',
	national: 'National',
	toll_free: 'TollFree'
};

const REGULATION_NUMBER_TYPE: Record<NumberType, string> = {
	local: 'local',
	mobile: 'mobile',
	national: 'national',
	toll_free: 'toll-free'
};

export class TwilioCatalogError extends Error {
	constructor(
		message: string,
		public readonly status: number | null,
		public readonly code: string,
		// 429, 5xx and network failures are a provider outage the caller may retry; a 4xx is a definite answer.
		public readonly retryable: boolean,
		public readonly providerCode: string | null = null
	) {
		super(message);
		this.name = 'TwilioCatalogError';
	}
}

export type CatalogCountry = {
	countryCode: string;
	name: string;
	beta: boolean;
	numberTypes: NumberType[];
};

export type NumberCapabilities = { sms: boolean; mms: boolean; voice: boolean };

export type AvailableNumber = {
	phoneNumber: string;
	friendlyName: string;
	countryCode: string;
	numberType: NumberType;
	locality: string | null;
	region: string | null;
	postalCode: string | null;
	capabilities: NumberCapabilities;
	addressRequirement: AddressRequirement;
	beta: boolean;
};

export type NumberSearchInput = {
	countryCode: string;
	numberType: NumberType;
	sms?: boolean;
	mms?: boolean;
	voice?: boolean;
	contains?: string;
	areaCode?: string;
	limit?: number;
};

export type RequirementField = {
	name: string;
	label: string;
	description: string;
	required: boolean;
	// Allowed values when Twilio constrains the field to a fixed list, e.g. ['YES', 'NO'].
	choices: string[] | null;
	// Twilio's own validation pattern when it gives one (an email or E.164 phone shape).
	pattern: string | null;
	// For a document field, the end-user field it must equal, e.g. 'business_name'.
	mustMatch: string | null;
};

export type EndUserRequirement = {
	requirementName: string;
	label: string;
	endUserType: string;
	fields: RequirementField[];
};

export type AcceptedDocument = {
	documentType: string;
	label: string;
	fields: RequirementField[];
};

export type DocumentRequirement = {
	requirementName: string;
	label: string;
	description: string;
	// Any one of these satisfies the requirement.
	acceptedDocuments: AcceptedDocument[];
};

export type NumberRegulation = {
	regulationSid: string;
	label: string;
	countryCode: string;
	numberType: NumberType;
	endUserType: EndUserType;
	endUser: EndUserRequirement[];
	documents: DocumentRequirement[];
};

export type RegulationQuery = {
	countryCode: string;
	numberType: NumberType;
	endUserType: EndUserType;
};

// Prices stay exact decimal strings in major units (e.g. '0.0075'), matching the numeric(14,6) provider-cost
// column; converting to cents would round away sub-cent message prices.
export type CountryNumberPrices = {
	countryCode: string;
	currency: string;
	monthly: Partial<Record<NumberType, string>>;
};

export type PriceRange = { min: string; max: string };

export type CountryMessagePrices = {
	countryCode: string;
	currency: string;
	inbound: Partial<Record<MessagePriceSenderType, string>>;
	// Outbound prices vary by the recipient's carrier; the range covers every carrier Twilio lists.
	outbound: Partial<Record<MessagePriceSenderType, PriceRange>>;
};

export type TwilioCountryCatalogClient = {
	/** Every country with numbers in stock now, and which number types it has. */
	listCountries(): Promise<CatalogCountry[]>;
	/** Numbers currently available to buy. An empty list means no stock matches, not an error. */
	searchNumbers(input: NumberSearchInput): Promise<AvailableNumber[]>;
	/** The paperwork Twilio requires for this number. Null when the country has no rule for it (e.g. the US). */
	getRegulation(query: RegulationQuery): Promise<NumberRegulation | null>;
	/** Monthly number prices. Null when Twilio publishes none for the country. */
	getNumberPrices(countryCode: string): Promise<CountryNumberPrices | null>;
	/** Inbound and outbound message prices. Null when Twilio publishes none for the country. */
	getMessagePrices(countryCode: string): Promise<CountryMessagePrices | null>;
};

export function createTwilioCountryCatalogClient(
	platform: TwilioPlatformEnv = getTwilioPlatformEnv()
): TwilioCountryCatalogClient {
	const auth = `Basic ${Buffer.from(
		`${platform.TWILIO_PROVISIONING_KEY_SID}:${platform.TWILIO_PROVISIONING_KEY_SECRET}`,
		'utf8'
	).toString('base64')}`;
	const accountPath = `/2010-04-01/Accounts/${platform.TWILIO_ACCOUNT_SID}`;

	return {
		async listCountries() {
			const rows = await readPages({
				base: TWILIO_API_BASE,
				path: `${accountPath}/AvailablePhoneNumbers.json`,
				query: { PageSize: '1000' },
				auth,
				listKey: 'countries'
			});
			const countries: CatalogCountry[] = [];
			for (const row of rows) {
				const countryCode = readString(row, 'country_code');
				const name = readString(row, 'country');
				if (!countryCode || !COUNTRY_CODE.test(countryCode) || !name) continue;
				const uris = readObject(row, 'subresource_uris') ?? {};
				const numberTypes = NUMBER_TYPES.filter((type) => type in uris);
				if (numberTypes.length === 0) continue;
				countries.push({ countryCode, name, beta: readBoolean(row, 'beta'), numberTypes });
			}
			return countries.sort((a, b) => a.name.localeCompare(b.name));
		},

		async searchNumbers(input) {
			const countryCode = requireCountryCode(input.countryCode);
			const query: Record<string, string> = {
				PageSize: String(Math.min(Math.max(input.limit ?? 20, 1), MAX_SEARCH_RESULTS))
			};
			if (input.sms) query.SmsEnabled = 'true';
			if (input.mms) query.MmsEnabled = 'true';
			if (input.voice) query.VoiceEnabled = 'true';
			if (input.contains !== undefined) {
				if (!SEARCH_CONTAINS.test(input.contains)) throw invalidInput('contains');
				query.Contains = input.contains;
			}
			if (input.areaCode !== undefined) {
				if (!AREA_CODE.test(input.areaCode)) throw invalidInput('areaCode');
				query.AreaCode = input.areaCode;
			}

			let body: unknown;
			try {
				({ body } = await catalogRequest({
					base: TWILIO_API_BASE,
					path: `${accountPath}/AvailablePhoneNumbers/${countryCode}/${SEARCH_PATH[input.numberType]}.json`,
					query,
					auth
				}));
			} catch (error) {
				// Twilio answers 404 when the country or number type has no inventory at all.
				if (error instanceof TwilioCatalogError && error.status === 404) return [];
				throw error;
			}
			return readArray(body, 'available_phone_numbers').flatMap((row) => {
				const parsed = parseAvailableNumber(row, input.numberType);
				return parsed ? [parsed] : [];
			});
		},

		async getRegulation({ countryCode, numberType, endUserType }) {
			const rows = await readPages({
				base: NUMBERS_BASE,
				path: '/v2/RegulatoryCompliance/Regulations',
				query: {
					IsoCountry: requireCountryCode(countryCode),
					NumberType: REGULATION_NUMBER_TYPE[numberType],
					EndUserType: endUserType,
					IncludeConstraints: 'true',
					PageSize: '20'
				},
				auth,
				listKey: 'results'
			});
			const row = rows.find(
				(candidate) =>
					readString(candidate, 'end_user_type') === endUserType &&
					readString(candidate, 'number_type') === REGULATION_NUMBER_TYPE[numberType]
			);
			if (!row) return null;
			const regulationSid = readString(row, 'sid');
			if (!regulationSid) return null;
			const requirements = readObject(row, 'requirements') ?? {};
			return {
				regulationSid,
				label: readString(row, 'friendly_name') ?? '',
				countryCode,
				numberType,
				endUserType,
				endUser: readArray(requirements, 'end_user').map(parseEndUserRequirement),
				// Twilio nests document requirements one level deeper (a list of requirement groups).
				documents: readArray(requirements, 'supporting_document')
					.flatMap((group) => (Array.isArray(group) ? group : [group]))
					.map(parseDocumentRequirement)
			};
		},

		async getNumberPrices(countryCode) {
			const body = await readPriceResource(
				`/v1/PhoneNumbers/Countries/${requireCountryCode(countryCode)}`,
				auth
			);
			if (!body) return null;
			const monthly: Partial<Record<NumberType, string>> = {};
			for (const row of readArray(body, 'phone_number_prices')) {
				const type = normalizeNumberType(readString(row, 'number_type'));
				const price = readPrice(row);
				if (type && type !== 'short_code' && price) monthly[type] = price;
			}
			return { countryCode, currency: readCurrency(body), monthly };
		},

		async getMessagePrices(countryCode) {
			const body = await readPriceResource(
				`/v1/Messaging/Countries/${requireCountryCode(countryCode)}`,
				auth
			);
			if (!body) return null;
			const inbound: Partial<Record<MessagePriceSenderType, string>> = {};
			for (const row of readArray(body, 'inbound_sms_prices')) {
				const type = normalizeNumberType(readString(row, 'number_type'));
				const price = readPrice(row);
				if (type && price) inbound[type] = price;
			}
			const outbound: Partial<Record<MessagePriceSenderType, PriceRange>> = {};
			for (const carrier of readArray(body, 'outbound_sms_prices')) {
				for (const row of readArray(carrier, 'prices')) {
					const type = normalizeNumberType(readString(row, 'number_type'));
					const price = readPrice(row);
					if (!type || !price) continue;
					const current = outbound[type];
					outbound[type] = current
						? {
								min: Number(price) < Number(current.min) ? price : current.min,
								max: Number(price) > Number(current.max) ? price : current.max
							}
						: { min: price, max: price };
				}
			}
			return { countryCode, currency: readCurrency(body), inbound, outbound };
		}
	};
}

// --- Parsing -----------------------------------------------------------------------------------------------------

function parseAvailableNumber(row: unknown, numberType: NumberType): AvailableNumber | null {
	const phoneNumber = readString(row, 'phone_number');
	const countryCode = readString(row, 'iso_country');
	if (!phoneNumber || !/^\+[1-9][0-9]{1,14}$/.test(phoneNumber) || !countryCode) return null;
	const capabilities = readObject(row, 'capabilities') ?? {};
	const address = readString(row, 'address_requirements');
	return {
		phoneNumber,
		friendlyName: readString(row, 'friendly_name') ?? phoneNumber,
		countryCode,
		numberType,
		locality: readString(row, 'locality'),
		region: readString(row, 'region'),
		postalCode: readString(row, 'postal_code'),
		capabilities: {
			sms: readCapability(capabilities, 'sms'),
			mms: readCapability(capabilities, 'mms'),
			voice: readCapability(capabilities, 'voice')
		},
		// An unknown value is treated as "an address is needed" so a purchase never skips paperwork.
		addressRequirement:
			address === 'none' || address === 'any' || address === 'local' || address === 'foreign'
				? address
				: 'any',
		beta: readBoolean(row, 'beta')
	};
}

function parseEndUserRequirement(row: unknown): EndUserRequirement {
	return {
		requirementName: readString(row, 'requirement_name') ?? '',
		label: readString(row, 'name') ?? '',
		endUserType: readString(row, 'type') ?? '',
		fields: parseFields(row)
	};
}

function parseDocumentRequirement(row: unknown): DocumentRequirement {
	return {
		requirementName: readString(row, 'requirement_name') ?? '',
		label: readString(row, 'name') ?? '',
		description: readString(row, 'description') ?? '',
		acceptedDocuments: readArray(row, 'accepted_documents').map((document) => ({
			documentType: readString(document, 'type') ?? '',
			label: readString(document, 'name') ?? '',
			fields: parseFields(document)
		}))
	};
}

function parseFields(row: unknown): RequirementField[] {
	const detailed = readArray(row, 'detailed_fields');
	if (detailed.length > 0) return detailed.map(parseField);
	// Without IncludeConstraints detail Twilio lists bare field names; treat each as required free text.
	return readArray(row, 'fields')
		.filter((name): name is string => typeof name === 'string')
		.map((name) => ({
			name,
			label: name,
			description: '',
			required: true,
			choices: null,
			pattern: null,
			mustMatch: null
		}));
}

export function parseField(row: unknown): RequirementField {
	const name = readString(row, 'machine_name') ?? '';
	const constraint = readString(row, 'constraint') ?? '';
	const match = /=~\s*'(.*)'\s*$/.exec(constraint);
	const pattern = match ? match[1] : null;
	// A pattern that is just a fixed list -- ^(A|B|C)$ -- is offered as choices instead of free text.
	const list = pattern ? /^\^\(([A-Za-z0-9_:|-]+)\)\$$/.exec(pattern) : null;
	const equals = /==\s*[a-z_]+\['([a-z_]+)'\]/.exec(constraint);
	return {
		name,
		label: readString(row, 'friendly_name') || name,
		description: (readString(row, 'description') ?? '').trim(),
		required: constraint.trim() !== '',
		choices: list ? list[1].split('|') : null,
		pattern: list ? null : pattern,
		mustMatch: equals ? equals[1] : null
	};
}

export function normalizeNumberType(value: string | null): MessagePriceSenderType | null {
	switch (value?.trim().toLowerCase()) {
		case 'local':
			return 'local';
		case 'mobile':
			return 'mobile';
		case 'national':
			return 'national';
		case 'toll free':
		case 'toll-free':
		case 'toll_free':
		case 'tollfree':
			return 'toll_free';
		case 'shortcode':
		case 'short code':
		case 'short_code':
			return 'short_code';
		default:
			return null;
	}
}

// --- Transport ---------------------------------------------------------------------------------------------------

type CatalogRequest = {
	base: string;
	path: string;
	auth: string;
	query?: Record<string, string>;
};

async function catalogRequest(request: CatalogRequest): Promise<{ body: unknown }> {
	const url = new URL(request.path, request.base);
	for (const [key, value] of Object.entries(request.query ?? {})) {
		url.searchParams.set(key, value);
	}

	const controller = new AbortController();
	const timeout = setTimeout(() => controller.abort(), PROVIDER_TIMEOUT_MS);
	let response: Response;
	try {
		response = await fetch(url, {
			method: 'GET',
			headers: { accept: 'application/json', authorization: request.auth },
			signal: controller.signal
		});
	} catch {
		// Never surface the underlying error text -- it can echo request headers, including credentials.
		throw new TwilioCatalogError(
			'Twilio did not return a result.',
			null,
			'twilio_catalog_unknown',
			true
		);
	} finally {
		clearTimeout(timeout);
	}

	let body: unknown = null;
	const text = await response.text().catch(() => '');
	if (text) {
		try {
			body = JSON.parse(text);
		} catch {
			body = null;
		}
	}

	if (!response.ok) {
		const providerCode =
			body &&
			typeof body === 'object' &&
			'code' in body &&
			typeof (body as { code: unknown }).code === 'number'
				? String((body as { code: number }).code)
				: null;
		const retryable = response.status === 429 || response.status >= 500;
		throw new TwilioCatalogError(
			`Twilio rejected a catalog request (status ${response.status}).`,
			response.status,
			'twilio_catalog_rejected',
			retryable,
			providerCode
		);
	}

	return { body };
}

async function readPages(request: CatalogRequest & { listKey: string }): Promise<unknown[]> {
	const rows: unknown[] = [];
	let next: CatalogRequest | null = request;
	for (let page = 0; next && page < MAX_PAGES; page++) {
		const { body } = await catalogRequest(next);
		rows.push(...readArray(body, request.listKey));
		next = nextPage(body, request);
	}
	return rows;
}

// The 2010 API returns a relative `next_page_uri`; the v1/v2 APIs return an absolute `meta.next_page_url`. Only a
// next page on the same host is followed, so a corrupted value can never send the credential elsewhere.
function nextPage(body: unknown, request: CatalogRequest): CatalogRequest | null {
	const relative = readString(body, 'next_page_uri');
	if (relative) return { base: request.base, path: relative, auth: request.auth };
	const absolute = readString(readObject(body, 'meta'), 'next_page_url');
	if (!absolute) return null;
	let url: URL;
	try {
		url = new URL(absolute);
	} catch {
		return null;
	}
	if (url.origin !== new URL(request.base).origin) return null;
	return { base: request.base, path: `${url.pathname}${url.search}`, auth: request.auth };
}

async function readPriceResource(path: string, auth: string): Promise<unknown | null> {
	try {
		const { body } = await catalogRequest({ base: PRICING_BASE, path, auth });
		return body;
	} catch (error) {
		if (error instanceof TwilioCatalogError && error.status === 404) return null;
		throw error;
	}
}

// --- Small readers -----------------------------------------------------------------------------------------------

function requireCountryCode(value: string): string {
	if (!COUNTRY_CODE.test(value)) throw invalidInput('countryCode');
	return value;
}

function invalidInput(field: string): TwilioCatalogError {
	return new TwilioCatalogError(
		`Invalid catalog input: ${field}.`,
		null,
		'twilio_catalog_invalid_input',
		false
	);
}

function readString(body: unknown, key: string): string | null {
	if (body && typeof body === 'object' && key in body) {
		const value = (body as Record<string, unknown>)[key];
		return typeof value === 'string' ? value : null;
	}
	return null;
}

function readBoolean(body: unknown, key: string): boolean {
	return Boolean(
		body && typeof body === 'object' && (body as Record<string, unknown>)[key] === true
	);
}

function readObject(body: unknown, key: string): Record<string, unknown> | null {
	if (body && typeof body === 'object' && key in body) {
		const value = (body as Record<string, unknown>)[key];
		return value && typeof value === 'object' && !Array.isArray(value)
			? (value as Record<string, unknown>)
			: null;
	}
	return null;
}

function readArray(body: unknown, key: string): unknown[] {
	if (body && typeof body === 'object' && key in body) {
		const value = (body as Record<string, unknown>)[key];
		return Array.isArray(value) ? value : [];
	}
	return [];
}

function readCapability(capabilities: Record<string, unknown>, key: string): boolean {
	return capabilities[key] === true || capabilities[key.toUpperCase()] === true;
}

function readPrice(row: unknown): string | null {
	const price = readString(row, 'current_price') ?? readString(row, 'base_price');
	return price && /^[0-9]+(\.[0-9]+)?$/.test(price.trim()) ? price.trim() : null;
}

function readCurrency(body: unknown): string {
	return (readString(body, 'price_unit') ?? 'USD').toUpperCase();
}
