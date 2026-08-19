import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { taskInputSchema } from '$lib/server/validation/pipeline.schema';
import { taskNotFound, taskWriteError, toTask, type TaskRow } from '$lib/server/pipeline/tasks';

// A Task lives under its Opportunity, but it is edited by its own id, so these two sit outside the
// opportunity route. Which Opportunity it belongs to, and whether the caller may touch it, are the
// write function's questions, not this route's.

export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = taskInputSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('pipeline_update_opportunity_task', {
		target_task_id: event.params.taskId,
		new_title: parsed.data.title,
		new_instructions: parsed.data.instructions,
		new_assignee_user_id: parsed.data.assignee_user_id,
		new_due_on: parsed.data.due_on
	});

	if (error) return taskWriteError(error);

	const updated = (data as TaskRow[] | null)?.[0];
	if (!updated) return taskNotFound();

	return json(toTask(updated), { headers: NO_STORE_HEADERS });
};

export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('pipeline_delete_task', {
		target_task_id: event.params.taskId
	});

	if (error) return taskWriteError(error);

	const deleted = (data as { id: string; opportunity_id: string }[] | null)?.[0];
	if (!deleted) return taskNotFound();

	// The Brief needs the Opportunity back to know which cached list to drop the Task from.
	return json(deleted, { headers: NO_STORE_HEADERS });
};
