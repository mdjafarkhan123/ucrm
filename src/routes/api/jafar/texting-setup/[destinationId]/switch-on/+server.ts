import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	alreadyFinished,
	destinationActorName,
	loadDestination
} from '$lib/server/communications/sms-destination-ops';
import {
	addedOptOutLanguages,
	missingOptOutLanguages
} from '$lib/server/communications/sms-opt-out-tasks';
import { languageName } from '$lib/communications/sms-opt-out-words';

// Stage 10 Part 5b: "Mark as turned on". The person ticked the country in the business's Twilio Geo
// permissions and says so; Twilio offers no way to check or switch it from software. Only a waiting country
// moves, so a second press, or a teammate's, finds it already done.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedId = organizationIdSchema.safeParse(event.params.destinationId);
	if (!parsedId.success) return json({ error: 'The task identifier is invalid.' }, { status: 422 });

	try {
		const client = getOwnerSupabaseClient();
		const existing = await loadDestination(client, parsedId.data);
		if (!existing) return json({ error: 'That task was not found.' }, { status: 404 });

		// Part 5d: a customer there must be able to reply STOP in their own language first.
		if (existing.status === 'setting_up') {
			const added = await addedOptOutLanguages(client, [existing.organization_id]);
			const missing = missingOptOutLanguages(
				existing.country_code,
				added.get(existing.organization_id)
			);
			if (missing.length) {
				const names = missing.map(languageName).join(' and ');
				return json(
					{ error: `Add the ${names} opt-out words first.`, opt_out_missing: missing },
					{ status: 409 }
				);
			}
		}

		const actorName = destinationActorName(session);
		const result = await client.rpc('communication_sms_switch_on_destination', {
			p_destination_id: parsedId.data,
			// No Supabase user signs in here (ready_by points at one); the name records who.
			p_actor: null as unknown as string,
			p_actor_name: actorName
		});
		if (result.error) throw result.error;
		if (!result.data?.id) return await alreadyFinished(client, parsedId.data);

		await recordOwnerAccessAudit(client, {
			organization_id: existing.organization_id,
			email: session.email,
			event_type: 'communication_sms_destination_switched_on',
			target_type: 'communication_sms_destination',
			target_key: parsedId.data,
			before_state: { status: existing.status },
			after_state: { status: 'ready', country_code: existing.country_code }
		});

		return json(
			{ destination: result.data, actor_name: actorName },
			{ headers: { 'cache-control': 'no-store' } }
		);
	} catch (error) {
		console.error('Could not mark the country as turned on.', error);
		return json({ error: 'The country could not be marked as turned on.' }, { status: 500 });
	}
};
