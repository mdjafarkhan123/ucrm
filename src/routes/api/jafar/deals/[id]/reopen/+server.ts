import { z } from 'zod';
import type { RequestHandler } from './$types';
import { notFound } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readBody } from '$lib/server/jafar/lead-approval';
import { DEAL_NOT_FOUND, dealCommandResponse } from '$lib/server/jafar/deals';
import { dealReopenSchema } from '$lib/server/validation/deal.schema';

// Jafar business management B4: reopen a Lost Deal into the stage it was lost from, with a new next step.

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(DEAL_NOT_FOUND);

	const body = await readBody(event.request, dealReopenSchema);
	if ('response' in body) return body.response;

	const result = await getOwnerSupabaseClient().rpc('owner_deal_reopen', {
		actor_email: session.email,
		target_deal_id: event.params.id,
		target_next_action: body.data.next_action.text,
		target_due_on: body.data.next_action.due_on
	});
	return dealCommandResponse(result, 'reopen the Deal');
};
