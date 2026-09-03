import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { scheduleEventWriteSchema } from '$lib/server/validation/schedule.schema';

// Schedule's first native write: creating a Schedule-owned Event. Events are the one calendar object Schedule
// owns outright (Visits belong to Jobs, Assessments to Requests), so unlike a visit move this does not defer
// to an owner command -- it writes its own table directly, behind the same jobs.schedule calendar-change
// authority every other calendar change uses. RLS enforces tenant membership; this route enforces the
// permission, so a member without it gets a clear 403 rather than an empty write.
export const POST: RequestHandler = async (event) => {
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
		.insert({ organization_id: check.auth.organization.id, ...parsed.data })
		.select('id, title, description, event_date, start_time, end_time, all_day')
		.single();

	if (error) return databaseError();

	return json({ event: data }, { headers: NO_STORE_HEADERS });
};
