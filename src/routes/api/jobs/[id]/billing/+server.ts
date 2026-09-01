import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { setJobBillingSchema } from '$lib/server/validation/jobs.schema';
import { updateJobError } from '$lib/server/jobs/errors';

// Two of the three billing decisions: how the work is priced, and when we remind ourselves to invoice.
// The third — how the money is actually collected — belongs to Payments and has no field here, so no
// billing choice can quietly switch on a charge. `set_job_billing` refuses a basis the job's type does not
// allow, which is why a one-off can never be talked into per-visit pricing from the browser.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = setJobBillingSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('set_job_billing', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		expected_revision: parsed.data.expected_revision,
		new_price_basis: parsed.data.price_basis,
		new_billing_timing: parsed.data.billing_timing
	});

	if (error) return updateJobError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
