import { z } from 'zod';
import type { RequestHandler } from './$types';
import { notFound } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readBody } from '$lib/server/jafar/lead-approval';
import { DEAL_NOT_FOUND, dealCommandResponse } from '$lib/server/jafar/deals';
import { dealMoveSchema } from '$lib/server/validation/deal.schema';

// Jafar business management B4: move a Deal to another open stage, with its next step. Call booked, Awaiting
// decision and Later need a new dated step; the others keep the current one unless a new one is given.

export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(DEAL_NOT_FOUND);

	const body = await readBody(event.request, dealMoveSchema);
	if ('response' in body) return body.response;

	const next = body.data.next_action;
	const result = await getOwnerSupabaseClient().rpc('owner_deal_move', {
		actor_email: session.email,
		target_deal_id: event.params.id,
		target_stage: body.data.stage,
		next_action_mode: next ? 'set' : 'keep',
		target_next_action: next?.text,
		target_due_on: next?.due_on
	});
	return dealCommandResponse(result, 'move the Deal');
};
