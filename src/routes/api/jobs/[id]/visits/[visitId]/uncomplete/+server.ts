import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { scheduleVisitError } from '$lib/server/jobs/errors';

// Clear a visit's completion. `uncomplete_job_visit` checks jobs.complete itself and is idempotent on an
// already-incomplete visit. Any reminder the completion already raised is left untouched.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('uncomplete_job_visit', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		target_visit_id: event.params.visitId
	});

	if (error) return scheduleVisitError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
