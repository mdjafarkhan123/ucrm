import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { setJobDiscountSchema } from '$lib/server/validation/jobs.schema';
import { updateJobError } from '$lib/server/jobs/errors';

// One discount on the job, with the name the customer reads. Sending a null type removes it. The same shape
// the quote's discount route uses, because it is the same decision made one step later in the lifecycle.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = setJobDiscountSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('set_job_discount', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		expected_revision: parsed.data.expected_revision,
		new_name: parsed.data.name,
		new_type: parsed.data.type ?? null,
		new_value: parsed.data.value ?? null
	});

	if (error) return updateJobError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
