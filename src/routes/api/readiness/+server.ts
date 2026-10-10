import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { requireSetupReader } from '$lib/server/setup/access';
import { loadMemberReadiness } from '$lib/server/experience/readiness';

// Which real-world areas Uplift has opened for this business, and for each area still closed the specific
// tasks left and who owns them (multi-industry foundation B8). Owners and administrators read it on the
// dashboard; the same answer gates the actions themselves. Uplift's private reasons never come with it.
export const GET: RequestHandler = async (event) => {
	const check = await requireSetupReader(event);
	if ('response' in check) return check.response;

	try {
		const areas = await loadMemberReadiness(event.locals.supabase, check.auth.organization.id);
		return json({ areas }, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not read operational readiness.', error);
		return databaseError();
	}
};
