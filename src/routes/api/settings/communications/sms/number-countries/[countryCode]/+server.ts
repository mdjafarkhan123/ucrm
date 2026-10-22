import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getSmsCountryCatalog } from '$lib/server/communications/sms-country-catalog';
import {
	listNumberKinds,
	loadBoughtBalance,
	loadNumberPrices
} from '$lib/server/communications/sms-number-shop';
import { smsNumberCountrySchema } from '$lib/server/validation/communications-sms-settings.schema';

const noStore = { 'Cache-Control': 'no-store' };

// The number kinds one country offers, for step 1 of Add number: what each can do, its selling price and what it
// needs (paperwork first, or registering after buying), plus the bought balance the bill is paid from.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const country = smsNumberCountrySchema.safeParse(event.params.countryCode);
	if (!country.success) {
		return json({ error: 'Choose a country.' }, { status: 422, headers: noStore });
	}

	const client = getOwnerSupabaseClient();
	let balance, prices;
	try {
		balance = await loadBoughtBalance(client, check.auth.organization.id);
		prices = await loadNumberPrices(client, country.data, balance.currencyCode);
	} catch (error) {
		console.error('Could not load the number prices.', error);
		return json({ error: 'The prices could not be loaded.' }, { status: 500, headers: noStore });
	}

	try {
		const kinds = await listNumberKinds(getSmsCountryCatalog(), prices, country.data);
		return json(
			{
				country_code: country.data,
				kinds,
				balance_minor: balance.balanceMinor,
				currency_code: balance.currencyCode
			},
			{ headers: noStore }
		);
	} catch (error) {
		console.error('Could not load the number kinds.', error);
		return json(
			{ error: 'The phone company could not be reached.', code: 'provider_unavailable' },
			{ status: 503, headers: noStore }
		);
	}
};
