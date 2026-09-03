import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	databaseError,
	notFound,
	validationError
} from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { scheduleEventWriteSchema } from '$lib/server/validation/schedule.schema';

const NOT_FOUND = 'That event could not be found.';

// Edit one Event's whole shape. The form saves as a whole, so this replaces every field in one update.
// jobs.schedule is required, exactly as a visit edit requires it; an Event has no completion state to protect
// and no revision, so the last save wins -- a lightweight block Jobber itself edits without a concurrency
// token. The organization filter keeps the write inside the tenant even before RLS.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.schedule');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = scheduleEventWriteSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase
		.from('schedule_events')
		.update(parsed.data)
		.eq('organization_id', check.auth.organization.id)
		.eq('id', event.params.id)
		.select('id, title, description, event_date, start_time, end_time, all_day')
		.maybeSingle();

	if (error) return databaseError();
	if (!data) return notFound(NOT_FOUND);

	return json({ event: data }, { headers: NO_STORE_HEADERS });
};

// Delete one Event outright -- the contract's hard delete behind an explicit confirm the browser owns.
// jobs.schedule is required; there is nothing to protect (no completion, no owner record) so the row is
// simply removed.
export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.schedule');
	if ('response' in check) return check.response;

	const { error } = await event.locals.supabase
		.from('schedule_events')
		.delete()
		.eq('organization_id', check.auth.organization.id)
		.eq('id', event.params.id);

	if (error) return databaseError();

	return json({ event: null }, { headers: NO_STORE_HEADERS });
};
