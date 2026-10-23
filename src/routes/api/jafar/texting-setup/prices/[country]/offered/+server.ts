import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordPlatformAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { destinationActorName } from '$lib/server/communications/sms-destination-ops';

const offeredSchema = z.object({ offered: z.boolean() }).strict();

// Stage 10 Part 6: a row's ⋯ › Stop offering / Offer again (Jafar 2026-10-23: status Off). Businesses can't ask for
// a country Uplift doesn't offer; any already texting there keep it until each is turned off.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const country = event.params.country;
	if (!/^[A-Z]{2}$/.test(country)) return json({ error: 'Choose a country.' }, { status: 422 });
	const parsed = offeredSchema.safeParse(await event.request.json().catch(() => null));
	if (!parsed.success)
		return json({ error: 'Say whether the country is offered.' }, { status: 422 });

	try {
		const client = getOwnerSupabaseClient();
		const actorName = destinationActorName(session);
		const result = await client.rpc('communication_sms_set_country_offered', {
			p_country_code: country,
			p_offered: parsed.data.offered,
			p_actor_name: actorName
		});
		if (result.error) throw result.error;

		await recordPlatformAudit(client, {
			email: session.email,
			event_type: parsed.data.offered
				? 'communication_sms_country_offered'
				: 'communication_sms_country_not_offered',
			target_type: 'communication_sms_country',
			target_key: country,
			after_state: result.data
		});
		return json({ country: result.data }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not change whether the country is offered.', error);
		return json({ error: 'Nothing was changed. Try again.' }, { status: 500 });
	}
};
