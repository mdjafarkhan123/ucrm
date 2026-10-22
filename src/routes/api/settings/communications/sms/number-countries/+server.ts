import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getSmsCountryCatalog } from '$lib/server/communications/sms-country-catalog';

const noStore = { 'Cache-Control': 'no-store' };

// Every country where Twilio has numbers in stock, for the Add number country picker, and the business's own country
// so the picker starts there. The app blocks no region (Jafar, 2026-10-22); the catalog caches the list for a few
// minutes.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	try {
		const [countries, settings] = await Promise.all([
			getSmsCountryCatalog().listCountries(),
			getOwnerSupabaseClient()
				.from('organization_settings')
				.select('country_code')
				.eq('organization_id', check.auth.organization.id)
				.maybeSingle()
		]);
		const home = settings.data?.country_code ?? null;
		return json(
			{
				home_country: countries.some((country) => country.countryCode === home) ? home : null,
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
