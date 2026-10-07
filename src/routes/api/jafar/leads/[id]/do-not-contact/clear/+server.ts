import { z } from 'zod';
import type { RequestHandler } from './$types';
import { notFound } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { LEAD_NOT_FOUND, approvalResponse, readBody } from '$lib/server/jafar/lead-approval';
import { leadDoNotContactSchema } from '$lib/server/validation/lead.schema';

// Jafar business management B3: lift Do not contact, on purpose and with a reason kept in the history. Needs
// "Approve who to contact".

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(LEAD_NOT_FOUND);

	const body = await readBody(event.request, leadDoNotContactSchema);
	if ('response' in body) return body.response;

	const result = await getOwnerSupabaseClient().rpc('owner_lead_set_do_not_contact', {
		actor_email: session.email,
		target_id: event.params.id,
		turn_on: false,
		reason: body.data.reason ?? undefined
	});
	return approvalResponse(result, 'lift Do not contact');
};
