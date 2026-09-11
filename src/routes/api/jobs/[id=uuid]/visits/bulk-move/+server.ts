import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { moveJobVisitsSchema } from '$lib/server/validation/jobs.schema';
import { scheduleVisitError } from '$lib/server/jobs/errors';

// Move a batch of visits forward or back by whole days. `move_job_visits` checks jobs.schedule, is idempotent
// by key so a retry cannot double-shift the dates, and silently skips unscheduled and completed visits —
// `moved_count` in the reply says how many actually moved.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = moveJobVisitsSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('move_job_visits', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		visit_ids: parsed.data.visit_ids,
		day_offset: parsed.data.day_offset,
		new_idempotency_key: parsed.data.idempotency_key,
		new_request_hash: parsed.data.request_hash
	});

	if (error) return scheduleVisitError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
