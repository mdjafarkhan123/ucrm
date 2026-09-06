import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { setJobPaymentScheduleSchema } from '$lib/server/validation/jobs.schema';
import { updateJobError } from '$lib/server/jobs/errors';

// A one-off job's payment stages, replaced in one save. `set_job_payment_schedule` checks jobs.edit and the
// job's type for itself, prices the stages through the one function that owns that arithmetic, and refuses
// any list that changes a stage an invoice already claims — so this route validates the shape and gets out
// of the way. An empty list removes the schedule and puts the job back on whole-job billing.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = setJobPaymentScheduleSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('set_job_payment_schedule', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		expected_revision: parsed.data.expected_revision,
		// `id` is what the pricing function reads a kept stage's identity from; the browser sends the longer
		// name so a payload is readable on its own.
		new_items: parsed.data.stages.map((stage) => ({
			id: stage.installment_id ?? null,
			description: stage.description,
			type: stage.type,
			value: stage.value
		}))
	});

	if (error) return updateJobError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
