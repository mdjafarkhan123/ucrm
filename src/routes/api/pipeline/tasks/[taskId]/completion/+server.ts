import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { taskCompletionSchema } from '$lib/server/validation/pipeline.schema';
import { taskNotFound, taskWriteError, toTask, type TaskRow } from '$lib/server/pipeline/tasks';

// Completing and reopening. Its own route because it is its own action: the Brief ticks a box, it does
// not resubmit the form. Sending the state the Task is already in is answered with the Task unchanged,
// so a double click or a retried request costs nothing.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = taskCompletionSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('pipeline_set_task_completed', {
		target_task_id: event.params.taskId,
		is_completed: parsed.data.completed
	});

	if (error) return taskWriteError(error);

	const updated = (data as TaskRow[] | null)?.[0];
	if (!updated) return taskNotFound();

	return json(toTask(updated), { headers: NO_STORE_HEADERS });
};
