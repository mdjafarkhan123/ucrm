import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { addJobVisitsSchema } from '$lib/server/validation/jobs.schema';
import { scheduleVisitError } from '$lib/server/jobs/errors';

// Add 1-20 visits to a job that already exists. `add_job_visits` checks jobs.schedule itself (and answers the
// same way for a job in another organization), appends the visits after the job's existing ones, and is
// idempotent by key — so a doubled click gets the first result back with `applied: false`. The route only
// proves the caller can see jobs here; the command is the sole writer.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = addJobVisitsSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('add_job_visits', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		// The command reads each visit straight off the jsonb, and the keys the schema produces are exactly the
		// ones it reads, so the validated data goes through untouched.
		visits: parsed.data.visits,
		new_idempotency_key: parsed.data.idempotency_key,
		new_request_hash: parsed.data.request_hash
	});

	if (error) return scheduleVisitError(error);

	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};
