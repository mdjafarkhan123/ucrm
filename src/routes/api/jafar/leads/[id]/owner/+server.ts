import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { LEAD_NOT_FOUND, readBody } from '$lib/server/jafar/lead-approval';
import { dealCommandResponse } from '$lib/server/jafar/deals';
import { teammatesWhoCan } from '$lib/server/jafar/team-choices';
import { leadOwnerSchema } from '$lib/server/validation/lead.schema';

// Jafar business management D3a: who owns a business -- Jafar by default, or a teammate who can change Leads &
// Deals. Its reminders, alerts and upcoming calls follow the owner; the change is written to its history. Anyone
// who can change Leads may hand one over (the gate checks that), as in Pipedrive and HubSpot.

type Client = ReturnType<typeof getOwnerSupabaseClient>;

const leadOwnerChoices = (client: Client) => teammatesWhoCan(client, 'leads', 'work');

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	try {
		return json(
			{ choices: await leadOwnerChoices(getOwnerSupabaseClient()) },
			{ headers: PRIVATE_READ_HEADERS }
		);
	} catch (error) {
		console.error('Could not list who can own a Lead.', error);
		return json({ error: 'Your team could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(LEAD_NOT_FOUND);

	const body = await readBody(event.request, leadOwnerSchema);
	if ('response' in body) return body.response;

	const client = getOwnerSupabaseClient();
	const memberId = body.data.member_id;
	if (memberId !== null) {
		try {
			const choices = await leadOwnerChoices(client);
			if (!choices.some((choice) => choice.id === memberId)) {
				return validationError(
					{ member_id: 'That teammate cannot change Leads & Deals. Change their access first.' },
					409
				);
			}
		} catch (error) {
			console.error('Could not check who can own a Lead.', error);
			return json({ error: 'Your team could not be loaded.' }, { status: 500 });
		}
	}

	const result = await client.rpc('owner_lead_set_owner', {
		actor_email: session.email,
		target_relationship_id: event.params.id,
		// Null hands the business back to Jafar; the generated types do not show the parameter can be null.
		target_member_id: memberId as string
	});
	return dealCommandResponse(result, 'change who owns the Lead', LEAD_NOT_FOUND);
};
