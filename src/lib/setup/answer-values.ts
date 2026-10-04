// Client onboarding A5d: the answer types that hold more than plain words (plan §2.1). The page works with
// every answer as text, so each of these travels as JSON text and is stored as real JSON, as hours are
// (`$lib/setup/hours`). Each parser returns the value to store, or why the text cannot be one.

type Parsed<T> = { value: T; error: null } | { value: null; error: string };

const ok = <T>(value: T): Parsed<T> => ({ value, error: null });
const fail = (error: string): Parsed<never> => ({ value: null, error });

function json(raw: string): unknown {
	try {
		return JSON.parse(raw);
	} catch {
		return undefined;
	}
}

/** The longest "Other" answer a client may type for a choice question that is not built in. */
export const OTHER_MAX_LENGTH = 100;

/**
 * A tick-several answer: the ticked choices' values, and at most one entry of the client's own words when
 * "Other" is offered. Kept in the order the client sent.
 */
export function parseSetupChoices(
	raw: string,
	rules: { options: { value: string }[]; allowOther: boolean; maxChoices?: number }
): Parsed<string[]> {
	const list = json(raw);
	if (!Array.isArray(list) || list.some((item) => typeof item !== 'string'))
		return fail('Tick at least one.');
	const items = list.map((item: string) => item.trim()).filter(Boolean);
	if (items.length === 0) return fail('Tick at least one.');
	if (new Set(items).size !== items.length) return fail('A choice is ticked twice.');
	const listed = new Set(rules.options.map((option) => option.value));
	const own = items.filter((item) => !listed.has(item));
	if (own.length > (rules.allowOther ? 1 : 0)) return fail('Tick choices from the list.');
	if (own.some((item) => item.length > OTHER_MAX_LENGTH))
		return fail(`Keep "Other" under ${OTHER_MAX_LENGTH} characters.`);
	if (rules.maxChoices && items.length > rules.maxChoices)
		return fail(`Tick up to ${rules.maxChoices}.`);
	return ok(items);
}

/** The values a tick-several answer's text holds, or null when it is not a list. */
export function setupChoiceList(raw: string | null | undefined): string[] | null {
	if (!raw?.startsWith('[')) return null;
	const list = json(raw);
	return Array.isArray(list) && list.every((item) => typeof item === 'string') ? list : null;
}

/**
 * A web address. A client may leave out "https://", as most people do when they type one; it is added. Only
 * an address a browser can open is kept.
 */
export function parseSetupUrl(raw: string): Parsed<string> {
	const text = raw.trim();
	const withScheme = /^[a-z][a-z0-9+.-]*:/i.test(text) ? text : `https://${text}`;
	let url: URL;
	try {
		url = new URL(withScheme);
	} catch {
		return fail('Enter a web address like example.com.');
	}
	if (
		(url.protocol !== 'https:' && url.protocol !== 'http:') ||
		!/^[^.\s]+(\.[^.\s]+)+$/.test(url.hostname) ||
		withScheme.length > 2000
	)
		return fail('Enter a web address like example.com.');
	return ok(withScheme);
}

// A plain decimal as a number field hands it over: digits, then up to two decimal places.
const DECIMAL = /^\d{1,12}(\.\d{1,2})?$/;

/** A number of things: zero or more, up to two decimal places. */
export function parseSetupNumber(raw: string): Parsed<number> {
	const text = raw.trim();
	if (!DECIMAL.test(text) || Number(text) > 999_999_999)
		return fail('Enter a number, like 12 or 2.5.');
	return ok(Number(text));
}

export function parseSetupPercentage(raw: string): Parsed<number> {
	const text = raw.trim();
	if (!DECIMAL.test(text) || Number(text) > 100) return fail('Enter a percentage from 0 to 100.');
	return ok(Number(text));
}

export type SetupMoney = { amount: string; currency: string };

function currencyDigits(currency: string): number | null {
	try {
		return new Intl.NumberFormat('en', { style: 'currency', currency }).resolvedOptions()
			.maximumFractionDigits as number;
	} catch {
		return null;
	}
}

/**
 * An amount of money, always kept with its currency so a later change of the business's currency cannot
 * change what was said. The amount stays decimal text, never a rounded number.
 */
export function parseSetupMoney(raw: string): Parsed<SetupMoney> {
	const money = json(raw) as Partial<SetupMoney> | undefined;
	const amount = typeof money?.amount === 'string' ? money.amount.trim() : '';
	const currency = typeof money?.currency === 'string' ? money.currency : '';
	const digits = /^[A-Z]{3}$/.test(currency) ? currencyDigits(currency) : null;
	if (digits === null) return fail('Choose your currency in "Your business" first.');
	const [whole, fraction = ''] = amount.split('.');
	if (!DECIMAL.test(amount) || fraction.length > digits || Number(whole) > 999_999_999)
		return fail(
			digits === 0 ? 'Enter a whole amount, like 150.' : 'Enter an amount, like 150 or 99.50.'
		);
	return ok({ amount, currency });
}

export const SETUP_DISTANCE_UNITS = [
	{ value: 'mi', label: 'miles' },
	{ value: 'km', label: 'km' }
] as const;

export const SETUP_DURATION_UNITS = [
	{ value: 'minutes', label: 'minutes' },
	{ value: 'hours', label: 'hours' },
	{ value: 'days', label: 'days' }
] as const;

export type SetupMeasure = { amount: number; unit: string };

/** A distance or a length of time: an amount above zero and its unit. */
export function parseSetupMeasure(
	raw: string,
	units: readonly { value: string }[],
	what: 'distance' | 'time'
): Parsed<SetupMeasure> {
	const measure = json(raw) as { amount?: unknown; unit?: unknown } | undefined;
	const amount = typeof measure?.amount === 'number' ? measure.amount : NaN;
	if (!units.some((unit) => unit.value === measure?.unit))
		return fail(`Choose the ${what === 'distance' ? 'unit' : 'minutes, hours or days'}.`);
	if (!(amount > 0) || amount > 100_000 || !DECIMAL.test(String(amount)))
		return fail(what === 'distance' ? 'Enter a distance, like 25.' : 'Enter a time, like 45.');
	return ok({ amount, unit: measure!.unit as string });
}

/** Where miles are the everyday unit; everywhere else the app serves uses kilometres. */
export function defaultDistanceUnit(country: string | null | undefined): 'mi' | 'km' {
	return country === 'US' || country === 'GB' ? 'mi' : 'km';
}

export const SETUP_COLOURS_MAX = 8;

/** Brand colours as six-digit codes like #1A73E8, in the client's order. */
export function parseSetupColours(raw: string): Parsed<string[]> {
	const list = json(raw);
	if (!Array.isArray(list) || list.length === 0) return fail('Add at least one colour.');
	if (list.length > SETUP_COLOURS_MAX) return fail(`Add up to ${SETUP_COLOURS_MAX} colours.`);
	const colours: string[] = [];
	for (const item of list) {
		if (typeof item !== 'string' || !/^#[0-9a-f]{6}$/i.test(item.trim()))
			return fail('Enter each colour as a code like #1A73E8.');
		colours.push(item.trim().toUpperCase());
	}
	if (new Set(colours).size !== colours.length) return fail('A colour is listed twice.');
	return ok(colours);
}

/** The most one stored answer may hold. Mirrors organization_setup_answers_value_size_check. */
export const SETUP_ANSWER_MAX_BYTES = 8000;

/**
 * How many bytes a stored answer takes as the database measures it — its JSON written the way Postgres
 * writes jsonb as text, with a space after each colon and comma. A long add-another list can pass every
 * row's own rule and still not fit, so the save is refused in plain words instead of by the database.
 */
export function setupStoredBytes(value: unknown): number {
	const text = (item: unknown): string => {
		if (Array.isArray(item)) return `[${item.map(text).join(', ')}]`;
		if (item && typeof item === 'object')
			return `{${Object.entries(item)
				.map(([key, inner]) => `${JSON.stringify(key)}: ${text(inner)}`)
				.join(', ')}}`;
		return JSON.stringify(item) ?? 'null';
	};
	return new TextEncoder().encode(text(value)).length;
}
