import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { addJobExpenseSchema } from '$lib/server/validation/jobs.schema';
import { expenseError } from '$lib/server/jobs/errors';

// One job's recorded expenses, and the total under them. `job_expenses_list` is definer and decides for
// itself what this reader may see — everyone's expenses with expenses.manage_team, their own with
// expenses.record, and money only with jobs.view_cost — so a reader who may see less simply gets less rather
// than a second gate here.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('job_expenses_list', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id
	});
	if (error) return expenseError(error);

	return json(data, { headers: PRIVATE_READ_HEADERS });
};

// Recording an expense. The gate here is jobs.view, the same one that lets a person open the job at all;
// which expenses they may record — their own, or anyone's — is decided by the command, which is also the
// only place that knows whether the job is closed. The receipt is not sent here: it attaches to the expense
// separately, through the attachment route, once this returns the new expense's id.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = addJobExpenseSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('add_job_expense', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		name: parsed.data.name,
		expense_date: parsed.data.expense_date,
		total_minor: parsed.data.total_minor,
		accounting_code: parsed.data.accounting_code ?? undefined,
		description: parsed.data.description ?? undefined,
		reimburse_to_user_id: parsed.data.reimburse_to_user_id ?? undefined
	});
	if (error) return expenseError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
