import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordPlatformAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	communicationSmsNumberRateSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

const noStore = { 'cache-control': 'no-store' };

// Stage 10 Part 2: every published number selling price version, newest first, with Twilio's cost beside it (Jafar-
// only truth). Part 6's Countries & prices tab reads this list.
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const { data, error } = await getOwnerSupabaseClient()
		.from('communication_sms_number_retail_rates')
		.select(
			'id, country_code, number_type, currency_code, monthly_rate_major, setup_rate_major, provider_monthly_cost_major, provider_setup_cost_major, effective_from, note, created_at'
		)
		.order('effective_from', { ascending: false });
	if (error) {
		console.error('Could not load the number prices.', error);
		return json({ error: 'The number prices could not be loaded.' }, { status: 500 });
	}
	return json({ rates: data ?? [] }, { headers: noStore });
};

// Jafar publishes a number's selling price. A change is a new version that applies to purchases from its start;
// orders already placed keep the version they were priced at.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = communicationSmsNumberRateSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the price.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422, headers: noStore }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const result = await client.rpc('communication_sms_set_number_rate', {
			p_country_code: parsed.data.country_code,
			p_number_type: parsed.data.number_type,
			p_monthly_rate_major: parsed.data.monthly_rate_major,
			p_set_by: PLATFORM_OWNER_ACTOR_ID,
			p_setup_rate_major: parsed.data.setup_rate_major,
			p_currency_code: parsed.data.currency_code,
			p_provider_monthly_cost_major: parsed.data.provider_monthly_cost_major,
			p_provider_setup_cost_major: parsed.data.provider_setup_cost_major,
			p_effective_from: parsed.data.effective_from,
			p_note: parsed.data.note
		});
		if (result.error) {
			if (['P0001', '23505', '23514'].includes(result.error.code ?? '')) {
				return json({ error: result.error.message }, { status: 409, headers: noStore });
			}
			throw result.error;
		}

		await recordPlatformAudit(client, {
			email: session.email,
			event_type: 'communication_sms_number_rate_set',
			target_type: 'communication_sms_number_retail_rate',
			target_key: result.data.id,
			before_state: null,
			after_state: result.data
		});

		return json({ rate: result.data }, { headers: noStore });
	} catch (error) {
		console.error('Could not publish the number price.', error);
		return json({ error: 'The price could not be published.' }, { status: 500, headers: noStore });
	}
};
