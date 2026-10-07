import { z } from 'zod';
import type { RequestHandler } from './$types';
import { notFound } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { LEAD_NOT_FOUND, approvalResponse, readBody } from '$lib/server/jafar/lead-approval';
import { leadSendBackSchema } from '$lib/server/validation/lead.schema';

// Jafar business management B3: send a Lead back to Researching with what needs fixing. Any approval is withdrawn.

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(LEAD_NOT_FOUND);

	const body = await readBody(event.request, leadSendBackSchema);
	if ('response' in body) return body.response;

	const result = await getOwnerSupabaseClient().rpc('owner_lead_send_back', {
		actor_email: session.email,
		target_id: event.params.id,
		reason: body.data.reason
	});
	return approvalResponse(result, 'send the Lead back');
};
