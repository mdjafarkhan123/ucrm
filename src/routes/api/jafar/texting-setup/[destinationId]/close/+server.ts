import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationSmsDestinationCloseSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import {
	alreadyFinished,
	destinationActorName,
	loadDestination
} from '$lib/server/communications/sms-destination-ops';


// Stage 10 Part 5b: "Can't turn on". The business's request closes with a reason for the log and the words the
// business sees instead of "Setting up". Texts waiting to go there are then refused by the route check.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedId = organizationIdSchema.safeParse(event.params.destinationId);
	if (!parsedId.success) return json({ error: 'The task identifier is invalid.' }, { status: 422 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}
	const parsed = communicationSmsDestinationCloseSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the request.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const existing = await loadDestination(client, parsedId.data);
		if (!existing) return json({ error: 'That task was not found.' }, { status: 404 });

		const result = await client.rpc('communication_sms_turn_off_destination', {
			p_destination_id: parsedId.data,
			// No Supabase user signs in here (ready_by points at one); the name records who.
			p_actor: null as unknown as string,
			p_reason: parsed.data.reason,
			p_business_message: parsed.data.business_message,
			p_closing: true,
			p_actor_name: destinationActorName(session)
		});
		if (result.error) throw result.error;
		if (!result.data?.id) return await alreadyFinished(client, parsedId.data);

		await recordOwnerAccessAudit(client, {
			organization_id: existing.organization_id,
			email: session.email,
			event_type: 'communication_sms_destination_closed',
			target_type: 'communication_sms_destination',
			target_key: parsedId.data,
			before_state: { status: existing.status },
			after_state: { status: 'off', country_code: existing.country_code, reason: parsed.data.reason }
		});

		return json({ destination: result.data }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not close the country request.', error);
		return json({ error: 'The request could not be closed.' }, { status: 500 });
	}
};
