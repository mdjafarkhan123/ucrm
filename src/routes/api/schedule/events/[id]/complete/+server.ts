import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { scheduleEventCompleteSchema } from '$lib/server/validation/schedule.schema';

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.schedule');
	if ('response' in check) return check.response;

	let body: unknown;
	try { body = await event.request.json(); }
	catch { return validationError({ form: 'Request body must be valid JSON.' }); }
	const parsed = scheduleEventCompleteSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const db = event.locals.supabase;
	// The conditional update makes retries and concurrent clicks preserve the original completion time.
	const { data, error } = await db.from('schedule_events')
		.update({ completed_at: new Date().toISOString() })
		.eq('organization_id', check.auth.organization.id).eq('id', event.params.id)
		.is('completed_at', null)
		.select('id, title, description, event_date, start_time, end_time, all_day, completed_at')
		.maybeSingle();
	if (error) return databaseError();
	if (data) return json({ event: data }, { headers: NO_STORE_HEADERS });

	const existing = await db.from('schedule_events')
		.select('id, title, description, event_date, start_time, end_time, all_day, completed_at')
		.eq('organization_id', check.auth.organization.id).eq('id', event.params.id).maybeSingle();
	if (existing.error) return databaseError();
	if (!existing.data) return notFound('That event could not be found.');
	return json({ event: existing.data }, { headers: NO_STORE_HEADERS });
};
