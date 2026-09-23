import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, notFound, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { getCampaignResults } from '$lib/server/marketing/campaigns';

// The campaign detail page's Results tab: delivery breakdown, credited work, and real revenue
// (blueprint §12-13). Needs marketing.view.

export const GET: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.view');
	if ('response' in access) return access.response;

	try {
		const results = await getCampaignResults(access.auth.organization.id, event.params.id);
		if (!results) return notFound('That campaign no longer exists.');
		return json({ results }, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not load marketing campaign results.', error);
		return databaseError();
	}
};
