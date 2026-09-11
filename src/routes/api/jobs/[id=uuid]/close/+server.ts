import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { jobLifecycleSchema } from '$lib/server/validation/jobs.schema';
import { jobLifecycleError } from '$lib/server/jobs/errors';

// "Finish job". `close_job` checks jobs.close itself, refuses a stale revision and a job that still has
// incomplete visits, is idempotent on an already-closed job, and fires the on_completion reminder when the
// job bills on closure.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = jobLifecycleSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('close_job', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		expected_revision: parsed.data.expected_revision
	});

	if (error) return jobLifecycleError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
