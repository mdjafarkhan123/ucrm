import type { SupabaseClient } from '@supabase/supabase-js';
import type { SmsCountryCatalog } from './sms-country-catalog';
import type { CountryMessagePrices, CountryNumberPrices } from './twilio-country-catalog';

// Stage 10 Part 6: "Check Twilio prices" on the Countries & prices tab. Asks Twilio's Pricing API for each listed
// country and records the answers; a cost that moved keeps the one before it (see
// `communication_sms_record_twilio_prices`). Outbound text prices vary by the recipient's carrier, so the dearest
// carrier is recorded: a margin worked out from it never turns out smaller than shown.

export type TwilioPriceRow = {
	country_code: string;
	kind: 'segment' | 'number_month';
	number_type: string;
	currency_code: string;
	cost_major: number;
};

const CONCURRENCY = 4;

export function twilioPriceRows(
	country: string,
	messages: CountryMessagePrices | null,
	numbers: CountryNumberPrices | null
): TwilioPriceRow[] {
	const rows: TwilioPriceRow[] = [];
	for (const [type, range] of Object.entries(messages?.outbound ?? {})) {
		if (!range) continue;
		rows.push({
			country_code: country,
			kind: 'segment',
			number_type: type,
			currency_code: messages!.currency,
			cost_major: Number(range.max)
		});
	}
	for (const [type, monthly] of Object.entries(numbers?.monthly ?? {})) {
		if (!monthly) continue;
		rows.push({
			country_code: country,
			kind: 'number_month',
			number_type: type,
			currency_code: numbers!.currency,
			cost_major: Number(monthly)
		});
	}
	return rows;
}

export type TwilioPriceCheck = { checked: string[]; failed: string[] };

export async function checkTwilioPrices(
	client: SupabaseClient,
	catalog: SmsCountryCatalog,
	countries: string[]
): Promise<TwilioPriceCheck> {
	// Asking again means asking Twilio, not the few-minutes cache.
	catalog.clear();

	const queue = [...new Set(countries)];
	const rows: TwilioPriceRow[] = [];
	const checked: string[] = [];
	const failed: string[] = [];

	async function worker() {
		for (let country = queue.shift(); country; country = queue.shift()) {
			try {
				const [messages, numbers] = await Promise.all([
					catalog.getMessagePrices(country),
					catalog.getNumberPrices(country)
				]);
				rows.push(...twilioPriceRows(country, messages, numbers));
				checked.push(country);
			} catch (error) {
				console.error(`Twilio prices for ${country} could not be read.`, error);
				failed.push(country);
			}
		}
	}
	await Promise.all(Array.from({ length: CONCURRENCY }, worker));

	if (rows.length) {
		const { error } = await client.rpc('communication_sms_record_twilio_prices', { p_rows: rows });
		if (error) throw error;
	}
	return { checked: checked.sort(), failed: failed.sort() };
}
