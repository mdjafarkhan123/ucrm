import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getSmsCountryCatalog } from '$lib/server/communications/sms-country-catalog';

const noStore = { 'Cache-Control': 'no-store' };

// Every country where Twilio has numbers in stock, for the Add number country picker. The app blocks no region
// (Jafar, 2026-10-22); the catalog caches the answer for a few minutes.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	try {
		const countries = await getSmsCountryCatalog().listCountries();
		return json(
			{
				countries: countries
					.map((country) => ({ country_code: country.countryCode, name: country.name }))
					.sort((a, b) => a.name.localeCompare(b.name))
			},
			{ headers: noStore }
		);
	} catch (error) {
		console.error('Could not load the number countries.', error);
		return json(
			{ error: 'The phone company could not be reached.', code: 'provider_unavailable' },
			{ status: 503, headers: noStore }
		);
	}
};
