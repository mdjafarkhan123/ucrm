import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { requireSetupReader } from '$lib/server/setup/access';
import { readReleasedPreviews } from '$lib/server/setup/preview';

// Client onboarding E3 (plan §6): every preview Uplift has released, newest first, with the team's notes on each.
// Read with the client's own session, so row security shows only released versions to owners and administrators.
export const GET: RequestHandler = async (event) => {
	const check = await requireSetupReader(event);
	if ('response' in check) return check.response;
	try {
		const versions = await readReleasedPreviews(event.locals.supabase, check.auth.organization.id);
		return json({ versions }, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not read the preview.', error);
		return databaseError();
	}
};
