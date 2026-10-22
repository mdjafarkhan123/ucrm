import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { settingsHomePermissions } from '$lib/server/settings/home-permissions';
import { loadSettingsHomeSummary } from '$lib/server/settings/home-summary';

// The captions on the Settings home ("GST 5% default", "84 items"). Its own read, so the home's rows and
// links show at once and the captions fill in as they arrive.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.business.view');
	if ('response' in check) return check.response;

	const summary = await loadSettingsHomeSummary({
		organizationId: check.auth.organization.id,
		supabase: event.locals.supabase,
		permissions: settingsHomePermissions(check.access)
	});
	return json(summary, { headers: PRIVATE_READ_HEADERS });
};
