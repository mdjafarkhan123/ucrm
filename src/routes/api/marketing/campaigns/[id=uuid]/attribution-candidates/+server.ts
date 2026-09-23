import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { listWindowAttributionCandidates } from '$lib/server/marketing/campaigns';

// The Results tab's "possible matches" browser (blueprint §13 method 3): uncredited work this campaign's
// last-touch window currently wins, for staff to review before declaring. Needs marketing.view -- declaring
// itself still needs marketing.draft, enforced by the existing POST .../credits route.

export const GET: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.view');
	if ('response' in access) return access.response;

	try {
		const candidates = await listWindowAttributionCandidates(
			access.auth.organization.id,
			event.params.id
		);
		return json({ candidates }, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not load marketing campaign attribution candidates.', error);
		return databaseError();
	}
};
