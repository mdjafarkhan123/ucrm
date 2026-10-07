import { z } from 'zod';
import type { RequestHandler } from './$types';
import { notFound } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { DEAL_NOT_FOUND, dealCommandResponse } from '$lib/server/jafar/deals';

// Jafar business management B4: remove a Deal started by mistake. Jafar's alone (the front-door gate keeps it
// from teammates); the business returns to the Leads list with one history line saying so.

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(DEAL_NOT_FOUND);

	const result = await getOwnerSupabaseClient().rpc('owner_deal_remove', {
		actor_email: session.email,
		target_deal_id: event.params.id
	});
	return dealCommandResponse(result, 'remove the Deal');
};
