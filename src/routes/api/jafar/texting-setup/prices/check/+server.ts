import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getSmsCountryCatalog } from '$lib/server/communications/sms-country-catalog';
import { checkTwilioPrices } from '$lib/server/communications/sms-country-prices';

const checkSchema = z
	.object({
		// Add a country asks for one country not yet on the list, so its pop-up can show Twilio's cost.
		country: z
			.string()
			.regex(/^[A-Z]{2}$/)
			.optional()
	})
	.strict();

// Stage 10 Part 6: Check Twilio prices. Asks Twilio again for every country on the list (or one new country) and
// records what moved. Read-only on Twilio's side; pressing it twice only asks twice.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsed = checkSchema.safeParse(await event.request.json().catch(() => ({})));
	if (!parsed.success) return json({ error: 'Choose a country.' }, { status: 422 });

	try {
		const client = getOwnerSupabaseClient();
		let countries: string[];
		if (parsed.data.country) {
			countries = [parsed.data.country];
		} else {
			const list = await client.rpc('communication_sms_price_list');
			if (list.error) throw list.error;
			const data = list.data as { countries: { country: string }[] } | null;
			countries = (data?.countries ?? []).map((row) => row.country);
		}

		const result = await checkTwilioPrices(client, getSmsCountryCatalog(), countries);
		if (countries.length && !result.checked.length) {
			return json({ error: 'Twilio could not be asked just now. Try again.' }, { status: 502 });
		}
		return json(
			{ checked_at: new Date().toISOString(), ...result },
			{ headers: { 'cache-control': 'no-store' } }
		);
	} catch (error) {
		console.error('Check Twilio prices failed.', error);
		return json({ error: 'Twilio could not be asked just now. Try again.' }, { status: 502 });
	}
};
