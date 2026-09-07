import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { addJobTimeEntrySchema } from '$lib/server/validation/jobs.schema';
import { timeEntryError } from '$lib/server/jobs/errors';

// One job's recorded hours, and the totals under them. `job_labor` is definer and decides for itself what
// this reader may see — everyone's hours with time.track_team, their own with time.track_own, and money only
// with jobs.view_cost — so a reader who may see less simply gets less rather than a second gate here.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('job_labor', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id
	});
	if (error) return timeEntryError(error);

	return json(data, { headers: PRIVATE_READ_HEADERS });
};

// Recording hours. The gate here is jobs.view, the same one that lets a person open the job at all; which
// hours they may record — their own, or anyone's — is decided by the command, which is also the only place
// that knows whether the job is closed. The rate is never sent from the browser: `add_job_time_entry` copies
// it from the person's profile at this moment, which is what makes a later rate change forward-only.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = addJobTimeEntrySchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('add_job_time_entry', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		target_user_id: parsed.data.user_id,
		started_at: parsed.data.started_at,
		minutes: parsed.data.minutes,
		target_visit_id: parsed.data.visit_id ?? undefined,
		notes: parsed.data.notes ?? undefined
	});
	if (error) return timeEntryError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
