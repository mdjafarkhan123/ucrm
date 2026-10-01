import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { loadLostReasons } from '$lib/server/pipeline/lost-reasons';

// The organization's lost reasons, for the "Mark as lost" and "Add reason" dialogs and for naming the
// reason on each Sales Outcomes row. Retired reasons come too, marked as such: the dialogs leave them out
// of new choices, but old records still carry them.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;

	const lookup = await loadLostReasons(event.locals.supabase, check.auth.organization.id);
	if (!lookup.ok) return databaseError();

	return json({ reasons: lookup.reasons }, { headers: PRIVATE_READ_HEADERS });
};
