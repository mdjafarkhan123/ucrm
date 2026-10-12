import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { runningTimerChangeSchema } from '$lib/server/validation/time-clock.schema';
import { readTimesheetBody } from '$lib/server/time-clock/body';
import { timesheetWriteError } from '$lib/server/time-clock/errors';
import { requireTimesheetReader } from '$lib/server/time-clock/timesheets';

// A person's running timer, changed from Timesheets: only its start and notes while it runs (plan §
// Timesheets page). A person changes their own; someone who manages the team's time, anyone's.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireTimesheetReader(event);
	if ('response' in check) return check.response;

	const body = await readTimesheetBody(event.request, runningTimerChangeSchema);
	if ('response' in body) return body.response;

	const { data, error } = await event.locals.supabase.rpc('update_running_timer', {
		target_organization_id: check.auth.organization.id,
		target_user_id: event.params.userId,
		work_day: body.data.day,
		start_time: body.data.start_time,
		notes: body.data.notes ?? undefined
	});
	if (error) return timesheetWriteError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
