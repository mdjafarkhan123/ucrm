import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, notFound } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { copyAcceptedSetupSettings } from '$lib/server/setup/settings-copy';

// Client onboarding C5: Jafar fills a client's CRM settings from their accepted setup answers again — after a
// copy that failed when he accepted, or to check them now. It copies everything accepted so far, so pressing it
// twice changes nothing, and it keeps any newer change the owner made in Settings (plan §4).

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');

	try {
		const results = await copyAcceptedSetupSettings(
			getOwnerSupabaseClient(),
			organizationId.data,
			session.email
		);
		return json({ results }, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not copy accepted setup answers into CRM settings.', error);
		return databaseError();
	}
};
