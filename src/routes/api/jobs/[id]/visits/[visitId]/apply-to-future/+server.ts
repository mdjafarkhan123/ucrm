import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { applyVisitToFutureSchema } from '$lib/server/validation/jobs.schema';
import { scheduleVisitError } from '$lib/server/jobs/errors';

// "Save and update future visits": copy this visit's time of day and/or crew onto the job's later visits.
// `apply_visit_to_future` checks jobs.schedule, skips completed and undated visits, and is idempotent by key.
// `updated_count` in the reply says how many visits actually took the change.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = applyVisitToFutureSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('apply_visit_to_future', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		source_visit_id: event.params.visitId,
		copy_time_of_day: parsed.data.time_of_day,
		copy_assigned_team: parsed.data.assigned_team,
		new_idempotency_key: parsed.data.idempotency_key,
		new_request_hash: parsed.data.request_hash
	});

	if (error) return scheduleVisitError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
