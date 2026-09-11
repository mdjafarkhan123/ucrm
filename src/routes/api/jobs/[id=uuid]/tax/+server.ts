import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { setJobTaxSchema } from '$lib/server/validation/jobs.schema';
import { updateJobError } from '$lib/server/jobs/errors';

// Re-resolve the effective default, freeze one saved rate, say No tax, or freeze a one-off custom rate — and
// optionally save that custom rate to the shared list, which the command checks settings.taxes.manage for
// rather than trusting the checkbox. Same five options a quote offers, from the same list.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = setJobTaxSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('set_job_tax', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		expected_revision: parsed.data.expected_revision,
		new_source: parsed.data.source,
		new_rate_id: parsed.data.rate_id,
		new_custom_name: parsed.data.custom_name,
		new_custom_rate_basis_points: parsed.data.custom_rate_basis_points ?? null,
		save_as_reusable: parsed.data.save_as_reusable
	});

	if (error) return updateJobError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
