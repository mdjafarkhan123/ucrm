import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { scheduleVisitError } from '$lib/server/jobs/errors';

// Mark a visit complete. `complete_job_visit` checks jobs.complete itself, is idempotent on an
// already-completed visit, fires the per-visit reminder when the job bills per completed visit, and reports
// final_visit when this was the last incomplete visit of a one-off job — the signal the browser uses to open
// the Finish job / Add a return visit / Keep open dialog.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('complete_job_visit', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		target_visit_id: event.params.visitId
	});

	if (error) return scheduleVisitError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
