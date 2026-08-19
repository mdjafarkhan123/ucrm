import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	PRIVATE_READ_HEADERS,
	NO_STORE_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { taskInputSchema } from '$lib/server/validation/pipeline.schema';
import {
	OPPORTUNITY_TASK_LIMIT,
	TASK_COLUMNS,
	taskNotFound,
	taskWriteError,
	toTask,
	type TaskRow
} from '$lib/server/pipeline/tasks';

// One Opportunity's Tasks, in the two groups the Brief shows them in.
//
// Two queries rather than one, run together: each group has its own partial index, and a single query
// asking for both would have to scan past the status filter. Neither can grow -- five each is the hard
// limit -- so there is no cursor here and never will be.
//
// The open group comes back in Jobber's card-priority order, which is the index's own column order:
// earliest due date first, undated Tasks last, ties broken by creation. That is what lets the card
// simply take the first one.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const opportunityId = event.params.id;

	const [openResult, completedResult] = await Promise.all([
		event.locals.supabase
			.from('tasks')
			.select(TASK_COLUMNS)
			.eq('organization_id', organizationId)
			.eq('opportunity_id', opportunityId)
			.eq('status', 'open')
			.order('due_on', { ascending: true, nullsFirst: false })
			.order('created_at', { ascending: true })
			.order('id', { ascending: true })
			.limit(OPPORTUNITY_TASK_LIMIT),
		event.locals.supabase
			.from('tasks')
			.select(TASK_COLUMNS)
			.eq('organization_id', organizationId)
			.eq('opportunity_id', opportunityId)
			.eq('status', 'completed')
			.order('completed_at', { ascending: false })
			.limit(OPPORTUNITY_TASK_LIMIT)
	]);

	if (openResult.error || completedResult.error) return databaseError();

	return json(
		{
			open: ((openResult.data ?? []) as TaskRow[]).map(toTask),
			completed: ((completedResult.data ?? []) as TaskRow[]).map(toTask)
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

export const POST: RequestHandler = async (event) => {
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

	const { data, error } = await event.locals.supabase.rpc('pipeline_create_opportunity_task', {
		target_opportunity_id: event.params.id,
		new_title: parsed.data.title,
		new_instructions: parsed.data.instructions,
		new_assignee_user_id: parsed.data.assignee_user_id,
		new_due_on: parsed.data.due_on
	});

	if (error) return taskWriteError(error);

	const created = (data as TaskRow[] | null)?.[0];
	if (!created) return taskNotFound();

	return json(toTask(created), { status: 201, headers: NO_STORE_HEADERS });
};
