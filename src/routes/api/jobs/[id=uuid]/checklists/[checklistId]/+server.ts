import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { checklistWriteError } from '$lib/server/checklists/errors';

// Taking a checklist off a job takes every visit's answers to it as well. The command reports how many went,
// and the screen asks before calling this -- so the count is a receipt, not a guard.
export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('remove_job_checklist', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		target_checklist_id: event.params.checklistId
	});

	if (error) return checklistWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
