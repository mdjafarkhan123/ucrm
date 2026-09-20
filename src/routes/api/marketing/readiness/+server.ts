import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { loadMarketingReadiness } from '$lib/server/marketing/readiness';

// What is stopping this organization from sending Marketing email. Needs marketing.view, which already folds in
// the plan: a plan without Marketing, or a member without the permission, gets a clear 403 and no facts at all.
export const GET: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.view');
	if ('response' in access) return access.response;

	// The menu only needs to know whether this member may see Marketing at all, so it asks for just that and
	// skips the readiness lookups.
	if (event.url.searchParams.get('access') === '1') {
		return json({ ok: true }, { headers: NO_STORE_HEADERS });
	}

	try {
		const readiness = await loadMarketingReadiness(access.auth.organization.id);
		return json(readiness, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not read Marketing readiness.', error);
		return json(
			{ error: 'We could not check Marketing readiness. Please try again.' },
			{ status: 500 }
		);
	}
};
