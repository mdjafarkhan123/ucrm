import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationSmsDestinationTurnOffSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import {
	destinationActorName,
	loadDestination
} from '$lib/server/communications/sms-destination-ops';

// Stage 10 Part 5b: Uplift turns a ready country off for one business, with a reason for the log. From then
// on the route check refuses texts there, including ones already waiting to go.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const parsedId = organizationIdSchema.safeParse(event.params.destinationId);
	if (!parsedOrganizationId.success || !parsedId.success) {
		return json({ error: 'The country identifier is invalid.' }, { status: 422 });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}
	const parsed = communicationSmsDestinationTurnOffSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the reason.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const existing = await loadDestination(client, parsedId.data);
		if (!existing || existing.organization_id !== parsedOrganizationId.data) {
			return json({ error: 'That country was not found.' }, { status: 404 });
		}

		const result = await client.rpc('communication_sms_turn_off_destination', {
			p_destination_id: parsedId.data,
			// No Supabase user signs in here (off_by points at one); the name records who.
			p_actor: null as unknown as string,
			p_reason: parsed.data.reason,
			p_business_message: '',
			p_closing: false,
			p_actor_name: destinationActorName(session)
		});
		if (result.error) throw result.error;
		if (!result.data?.id) {
			return json({ error: 'This country is not on any more.' }, { status: 409 });
		}

		await recordOwnerAccessAudit(client, {
			organization_id: existing.organization_id,
			email: session.email,
			event_type: 'communication_sms_destination_turned_off',
			target_type: 'communication_sms_destination',
			target_key: parsedId.data,
			before_state: { status: existing.status },
			after_state: { status: 'off', country_code: existing.country_code, reason: parsed.data.reason }
		});

		return json({ destination: result.data }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not turn the country off.', error);
		return json({ error: 'The country could not be turned off.' }, { status: 500 });
	}
};
