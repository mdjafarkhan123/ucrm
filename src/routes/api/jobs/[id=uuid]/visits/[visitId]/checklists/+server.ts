import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS, validationError } from '$lib/server/api/errors';
import { checklistReadError, checklistWriteError } from '$lib/server/checklists/errors';
import { visitChecklistAnswersSchema } from '$lib/server/validation/checklists.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// One visit's forms, with that visit's own answers and how many required questions are still blank. The
// completion prompt reads `outstanding_required`; it warns, it never blocks.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('visit_checklist_rows', {
		target_organization_id: check.auth.organization.id,
		target_visit_id: event.params.visitId
	});

	if (error) return checklistReadError(error);
	return json(data, { headers: PRIVATE_READ_HEADERS });
};

// Saving is partial on purpose: only the questions in the body are touched, and an empty answer clears that
// one question rather than the form. `save_visit_checklist_answers` checks field_records.record, so a crew
// member fills this in without holding any job editing right.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = visitChecklistAnswersSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('save_visit_checklist_answers', {
		target_organization_id: check.auth.organization.id,
		target_visit_id: event.params.visitId,
		answers: parsed.data.answers
	});

	if (error) return checklistWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
