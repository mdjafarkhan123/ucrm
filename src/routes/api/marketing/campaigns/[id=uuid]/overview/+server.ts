import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, notFound, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { getCampaignOverview } from '$lib/server/marketing/campaigns';

// The campaign detail page's Overview tab: summary, customer group name, and recipient bucket counts.
// Needs marketing.view, the same read tier as the campaign draft route.

export const GET: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.view');
	if ('response' in access) return access.response;

	try {
		const overview = await getCampaignOverview(access.auth.organization.id, event.params.id);
		if (!overview) return notFound('That campaign no longer exists.');
		return json({ overview }, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not load a marketing campaign overview.', error);
		return databaseError();
	}
};
