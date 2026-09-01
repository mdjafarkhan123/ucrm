import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { deleteJobVisitSchema, updateJobVisitSchema } from '$lib/server/validation/jobs.schema';
import { scheduleVisitError } from '$lib/server/jobs/errors';

// Edit one visit's whole schedule shape, title, instructions and crew. `update_job_visit` checks
// jobs.schedule, refuses a completed visit or a stale revision, and hands back the visit's new revision for
// the next edit. The assignee set replaces the visit's crew exactly.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = updateJobVisitSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('update_job_visit', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		target_visit_id: event.params.visitId,
		expected_revision: parsed.data.expected_revision,
		new_visit_date: parsed.data.visit_date,
		new_start_time: parsed.data.start_time,
		new_end_time: parsed.data.end_time,
		new_all_day: parsed.data.all_day,
		new_title: parsed.data.title,
		new_instructions: parsed.data.instructions,
		new_assignee_ids: parsed.data.assignee_ids
	});

	if (error) return scheduleVisitError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};

// Remove one visit. `delete_job_visit` checks jobs.schedule, protects a completed visit, and refuses a stale
// revision so a delete cannot remove a visit someone else has since changed. The revision the browser last
// read travels in the body.
export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = deleteJobVisitSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('delete_job_visit', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		target_visit_id: event.params.visitId,
		expected_revision: parsed.data.expected_revision
	});

	if (error) return scheduleVisitError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
