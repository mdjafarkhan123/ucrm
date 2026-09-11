import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { deleteJobExpenseSchema, updateJobExpenseSchema } from '$lib/server/validation/jobs.schema';
import { expenseError } from '$lib/server/jobs/errors';

// Correcting a recorded expense. Who recorded it is not in the payload and cannot change: created_by is what
// the own-level gate reads, so moving it would hand that access to someone else. The command keeps the
// recorder and writes the before and after to the job's costing trail.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = updateJobExpenseSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('update_job_expense', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		target_expense_id: event.params.expenseId,
		name: parsed.data.name,
		expense_date: parsed.data.expense_date,
		total_minor: parsed.data.total_minor,
		accounting_code: parsed.data.accounting_code ?? undefined,
		description: parsed.data.description ?? undefined,
		reimburse_to_user_id: parsed.data.reimburse_to_user_id ?? undefined,
		reason: parsed.data.reason ?? undefined
	});
	if (error) return expenseError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};

// Removing an expense recorded in error. The whole row is written to the costing trail before it goes, so
// deleting an expense never deletes the evidence that it existed. The receipt files are removed by the
// browser through the attachment route first, because R2 is reachable only from there.
export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	let body: unknown = {};
	try {
		const text = await event.request.text();
		if (text) body = JSON.parse(text);
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = deleteJobExpenseSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('delete_job_expense', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		target_expense_id: event.params.expenseId,
		reason: parsed.data.reason ?? undefined
	});
	if (error) return expenseError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
