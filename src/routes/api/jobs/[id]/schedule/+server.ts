import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { rescheduleJobVisitsSchema } from '$lib/server/validation/jobs.schema';
import { scheduleVisitError } from '$lib/server/jobs/errors';

// "Edit all visits": replace a recurring job's repeat rule and rebuild its incomplete visits from it.
// `reschedule_job_visits` checks jobs.schedule, refuses a one-off, an as-needed or a closed job, refuses a
// revision the browser read before someone else's change, and is idempotent by key so a retried request
// returns the first result instead of rebuilding the schedule twice. Completed visits are never in scope, and
// the visits table's own trigger holds that line whatever calls it.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = rescheduleJobVisitsSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('reschedule_job_visits', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		expected_revision: parsed.data.expected_revision,
		new_recurrence: parsed.data.recurrence,
		new_idempotency_key: parsed.data.idempotency_key,
		new_request_hash: parsed.data.request_hash
	});

	if (error) return scheduleVisitError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
