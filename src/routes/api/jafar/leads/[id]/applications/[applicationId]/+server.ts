import { z } from 'zod';
import type { RequestHandler } from './$types';
import { databaseError, notFound } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { linkResultResponse } from '$lib/server/jafar/lead-history';

// Jafar business management B2: unlinking an Application from this Lead -- for one linked by mistake. The
// Application itself is untouched; the history records the unlink.

export const DELETE: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (
		!z.uuid().safeParse(event.params.id).success ||
		!z.uuid().safeParse(event.params.applicationId).success
	)
		return notFound('This Application is not linked to this Lead.');

	try {
		const { data, error } = await getOwnerSupabaseClient().rpc('owner_lead_link_application', {
			actor_email: session.email,
			target_id: event.params.id,
			target_application_id: event.params.applicationId,
			target_link: false
		});
		if (error) throw error;
		return linkResultResponse(data);
	} catch (error) {
		console.error('Could not unlink the Application.', error);
		return databaseError();
	}
};
