import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import type { SmsCountryCatalog } from './sms-country-catalog';
import type { AvailableNumber, NumberType } from './twilio-country-catalog';

// What the Add number pop-up reads (Stage 10 Part 2): the countries with numbers in stock, each number kind with what
// it can do, its selling price and what it needs, and live numbers to choose from. Prices are Jafar's selling prices
// (communication_sms_number_retail_rates), never Twilio's cost, which stays Jafar-only.

// US and Canadian numbers need no paperwork to buy; they register for texting afterwards (10DLC or toll-free
// verification), as GoHighLevel shows at purchase.
const REGISTER_AFTER_COUNTRIES = new Set(['US', 'CA']);

export type NumberKindNeed = 'none' | 'register_after' | 'paperwork_first';

export type NumberPrice = { monthlyMinor: number; setupMinor: number; currencyCode: string };

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

export type ShopNumber = {
	phone_number: string;
	friendly_name: string;
	locality: string | null;
	region: string | null;
	capabilities: { sms: boolean; mms: boolean; voice: boolean };
	address_requirement: string;
};

function toMinor(major: number | string): number {
	return Math.round(Number(major) * 100);
}

/** Jafar's current selling price for each number kind in a country. */
export async function loadNumberPrices(
	client: SupabaseClient<Database>,
	countryCode: string,
	currencyCode = 'USD'
): Promise<Map<NumberType, NumberPrice>> {
	const { data, error } = await client
		.from('communication_sms_number_retail_rates')
		.select('number_type, monthly_rate_major, setup_rate_major, currency_code, effective_from')
		.eq('country_code', countryCode)
		.eq('currency_code', currencyCode)
		.lte('effective_from', new Date().toISOString())
		.order('effective_from', { ascending: false });
	if (error) throw new Error('Could not load the number prices.');

	const prices = new Map<NumberType, NumberPrice>();
	for (const row of data ?? []) {
		const numberType = row.number_type as NumberType;
		if (prices.has(numberType)) continue;
		prices.set(numberType, {
			monthlyMinor: toMinor(row.monthly_rate_major),
			setupMinor: toMinor(row.setup_rate_major),
			currencyCode: row.currency_code
		});
	}
	return prices;
}

/** The money the business has bought and not yet committed; numbers are paid from this, never promotional credit. */
export async function loadBoughtBalance(
	client: SupabaseClient<Database>,
	organizationId: string
): Promise<{ balanceMinor: number; currencyCode: string }> {
	const { data, error } = await client
		.from('communication_sms_credit_accounts')
		.select('settled_balance_minor, reserved_balance_minor, currency_code')
		.eq('organization_id', organizationId)
		.maybeSingle();
	if (error) throw new Error('Could not load the balance.');
	if (!data) return { balanceMinor: 0, currencyCode: 'USD' };
	return {
		balanceMinor: Number(data.settled_balance_minor) - Number(data.reserved_balance_minor),
		currencyCode: data.currency_code
	};
}

export async function listNumberKinds(
	catalog: Pick<SmsCountryCatalog, 'listNumberTypeOptions' | 'getRegulation'>,
	prices: Map<NumberType, NumberPrice>,
	countryCode: string,
	// Kinds whose paperwork this business already has approved: they can be bought straight away.
	approvedPaperwork: ReadonlySet<NumberType> = new Set()
): Promise<NumberKind[]> {
	const options = await catalog.listNumberTypeOptions(countryCode);
	return Promise.all(
		options.map(async (option) => {
			let needs: NumberKindNeed = 'none';
			if (REGISTER_AFTER_COUNTRIES.has(countryCode)) {
				needs = 'register_after';
			} else if (option.canText) {
				const regulation = await catalog.getRegulation({
					countryCode,
					numberType: option.numberType,
					endUserType: 'business'
				});
				const needsAddress =
					option.addressRequirement !== null && option.addressRequirement !== 'none';
				if ((regulation || needsAddress) && !approvedPaperwork.has(option.numberType)) {
					needs = 'paperwork_first';
				}
			}
			const price = prices.get(option.numberType);
			return {
				number_type: option.numberType,
				can_text: option.canText,
				can_send_pictures: option.canSendPictures,
				can_call: option.canCall,
				monthly_minor: price?.monthlyMinor ?? null,
				setup_minor: price?.setupMinor ?? null,
				currency_code: price?.currencyCode ?? 'USD',
				needs
			};
		})
	);
}

export function toShopNumber(number: AvailableNumber): ShopNumber {
	return {
		phone_number: number.phoneNumber,
		friendly_name: number.friendlyName,
		locality: number.locality,
		region: number.region,
		capabilities: number.capabilities,
		address_requirement: number.addressRequirement
	};
}
