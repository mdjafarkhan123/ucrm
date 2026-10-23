import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordPlatformAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { destinationActorName } from '$lib/server/communications/sms-destination-ops';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

const noStore = { 'cache-control': 'no-store' };

// Stage 10 Part 6: the Countries & prices tab of Texting setup (`concept.pen` card `R6mF2`). One price list for every
// business, with Twilio's cost beside each price (Jafar-only truth, never sent to a business route).
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const { data, error } = await getOwnerSupabaseClient().rpc('communication_sms_price_list');
	if (error) {
		console.error('Could not load the price list.', error);
		return json({ error: 'The price list could not be loaded.' }, { status: 500 });
	}
	return json(data, { headers: noStore });
};

const price = z.number().positive().max(1000).nullable();

const priceSchema = z
	.object({
		country: z.string().regex(/^[A-Z]{2}$/, 'Choose a country.'),
		segment: price,
		mms: price,
		number_month: price,
		// Null starts it now; a later day starts it at that day's start, never in the past.
		starts: z.iso.datetime({ offset: true }).nullable()
	})
	.strict()
	.refine((input) => input.segment !== null || input.mms !== null || input.number_month !== null, {
		message: 'Type at least one price.',
		path: ['segment']
	});

// The Change price pop-up (`dc8G7`), also opened by Add a country and Review price. Saves new price versions only;
// texts already sent keep the price they were sent at.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsed = priceSchema.safeParse(await event.request.json().catch(() => null));
	if (!parsed.success) {
		return json(
			{ error: parsed.error.issues[0]?.message ?? 'Please review the prices.' },
			{ status: 422, headers: noStore }
		);
	}
	const input = parsed.data;
	if (input.starts && new Date(input.starts).getTime() < Date.now() - 60_000) {
		return json({ error: 'Pick today or a later day.' }, { status: 422, headers: noStore });
	}

	try {
		const client = getOwnerSupabaseClient();
		const actorName = destinationActorName(session);
		const result = await client.rpc('communication_sms_set_country_price', {
			p_country_code: input.country,
			p_segment: input.segment as number,
			p_mms: input.mms as number,
			p_number_month: input.number_month as number,
			p_effective_from: input.starts as string,
			p_set_by: PLATFORM_OWNER_ACTOR_ID,
			p_actor_name: actorName
		});
		if (result.error) {
			if (['P0001', '23505', '23514'].includes(result.error.code ?? '')) {
				return json({ error: result.error.message }, { status: 409, headers: noStore });
			}
			throw result.error;
		}

		await recordPlatformAudit(client, {
			email: session.email,
			event_type: 'communication_sms_country_price_set',
			target_type: 'communication_sms_country',
			target_key: input.country,
			before_state: null,
			after_state: { ...input, actor_name: actorName }
		});

		return json(result.data, { headers: noStore });
	} catch (error) {
		console.error('Could not save the country price.', error);
		return json({ error: 'The price could not be saved.' }, { status: 500, headers: noStore });
	}
};
