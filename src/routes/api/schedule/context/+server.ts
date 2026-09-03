import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';

// What the calendar needs to know before it can mean anything: which timezone the contractor works in,
// which day that makes today, and which hours of the week are working hours.
//
// It is its own read because it barely ever changes. The window read below runs again on every date change;
// this one is fetched once and reused, so clicking through the weeks never re-sends the opening hours.
//
// public.schedule_calendar_context is the sole source. It is security definer, and it checks membership and
// jobs.view for itself, so a caller who slipped past the route check still gets nothing.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('schedule_calendar_context', {
		target_organization_id: check.auth.organization.id
	});

	if (error) return databaseError();
	// Null is the function's own refusal, not an empty answer. The route already proved the permission, so
	// reaching this means the two disagree, and the honest response is the refusal the function made.
	if (data === null) return databaseError();

	return json(
		{
			...(data as Record<string, unknown>),
			// Whether this person may change the calendar at all -- drag, resize and reassignment of existing
			// visits. Part 2 uses it to keep unavailable actions honestly absent rather than failing on click.
			can_schedule: hasPermission(check.access, 'jobs.schedule'),
			// Empty calendar space starts a Job, not a loose visit, so its affordance follows the Job-create
			// authority the /api/jobs command enforces -- a scheduler without it never sees a create surface
			// that Save would only reject.
			can_create_job: hasPermission(check.access, 'jobs.create'),
			// Completion is the Jobs-owned authority Part 13a introduced. Schedule presents complete/uncomplete
			// only to a reader who holds it, so an unavailable action stays honestly absent rather than failing
			// on click; the complete_job_visit command checks it again for itself.
			can_complete: hasPermission(check.access, 'jobs.complete'),
			// Finishing (closing) or reopening a job is a separate authority. It gates the "Finish job" option in
			// the final-visit dialog; the other two options need no close right.
			can_close: hasPermission(check.access, 'jobs.close')
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
