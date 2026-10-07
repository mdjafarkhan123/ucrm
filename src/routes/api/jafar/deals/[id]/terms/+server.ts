import { z } from 'zod';
import type { RequestHandler } from './$types';
import { notFound } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readBody } from '$lib/server/jafar/lead-approval';
import { DEAL_NOT_FOUND, dealCommandResponse } from '$lib/server/jafar/deals';
import { dealTermsSchema } from '$lib/server/validation/deal.schema';

// Jafar business management B4: the special terms agreed on a Deal ("first month free"). Its own sensitive
// action, "Agree special terms", so a teammate needs Jafar's grant (the front-door gate checks it).

export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(DEAL_NOT_FOUND);

	const body = await readBody(event.request, dealTermsSchema);
	if ('response' in body) return body.response;

	const result = await getOwnerSupabaseClient().rpc('owner_deal_set_terms', {
		actor_email: session.email,
		target_deal_id: event.params.id,
		terms: body.data.terms ?? undefined
	});
	return dealCommandResponse(result, 'save the agreed terms');
};
