import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { pipelineBulkSchema } from '$lib/server/validation/pipeline.schema';
import type { BulkCardResult } from '$lib/pipeline/bulk';

// The Table's bulk tools. `pipeline_bulk_update` runs each card through the same function its own single-card
// route uses, so every rule is enforced once, and answers per card — a refusal on one card never undoes the
// others. This route only shapes the request; the per-card answers go back as they are.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = pipelineBulkSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	const input = parsed.data;

	// The generated types read every defaulted argument as a non-null string, so a "clear it" null is left
	// out and the function's own `default null` stands in for it.
	const { data, error } = await event.locals.supabase.rpc('pipeline_bulk_update', {
		target_opportunity_ids: input.opportunity_ids,
		bulk_action: input.action,
		...(input.action === 'owner' && input.owner_user_id
			? { new_owner_user_id: input.owner_user_id }
			: {}),
		...(input.action === 'place' ? { target_custom_stage_id: input.custom_stage_id } : {}),
		...(input.action === 'task'
			? {
					new_title: input.task.title,
					...(input.task.instructions ? { new_instructions: input.task.instructions } : {}),
					...(input.task.assignee_user_id
						? { new_assignee_user_id: input.task.assignee_user_id }
						: {}),
					...(input.task.due_on ? { new_due_on: input.task.due_on } : {})
				}
			: {})
	});

	if (error) {
		if (error.code === '54000') return validationError({ form: error.message });
		return databaseError();
	}

	return json({ results: data as BulkCardResult[] }, { headers: NO_STORE_HEADERS });
};
