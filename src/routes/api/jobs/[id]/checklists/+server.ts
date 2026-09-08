import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS, validationError } from '$lib/server/api/errors';
import { checklistReadError, checklistWriteError } from '$lib/server/checklists/errors';
import { jobChecklistAttachSchema } from '$lib/server/validation/checklists.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// The checklists on one job, with the questions frozen onto it. `job_checklists_list` applies the assigned
// scope itself, so a Field member sees this only for a job they are on.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('job_checklists_list', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id
	});

	if (error) return checklistReadError(error);
	return json(data, { headers: PRIVATE_READ_HEADERS });
};

// Attaching copies the template's questions onto the job. `attach_job_checklist` checks jobs.edit, refuses a
// closed job, an archived template and the same checklist twice.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = jobChecklistAttachSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('attach_job_checklist', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		target_template_id: parsed.data.template_id
	});

	if (error) return checklistWriteError(error);
	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};
