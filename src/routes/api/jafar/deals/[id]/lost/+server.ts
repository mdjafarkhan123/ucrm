import { z } from 'zod';
import type { RequestHandler } from './$types';
import { notFound } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readBody } from '$lib/server/jafar/lead-approval';
import { DEAL_NOT_FOUND, dealCommandResponse } from '$lib/server/jafar/deals';
import { dealLostSchema } from '$lib/server/validation/deal.schema';

// Jafar business management B4: mark a Deal Lost with its reason. Its next step is cleared; the Deal stays in the
// business's history and can be reopened.

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(DEAL_NOT_FOUND);

	const body = await readBody(event.request, dealLostSchema);
	if ('response' in body) return body.response;

	const result = await getOwnerSupabaseClient().rpc('owner_deal_mark_lost', {
		actor_email: session.email,
		target_deal_id: event.params.id,
		reason: body.data.reason,
		note: body.data.note ?? undefined
	});
	return dealCommandResponse(result, 'mark the Deal Lost');
};
