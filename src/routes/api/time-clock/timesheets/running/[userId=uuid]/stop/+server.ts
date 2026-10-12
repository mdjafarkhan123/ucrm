import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { stopTimerAtSchema } from '$lib/server/validation/time-clock.schema';
import { readTimesheetBody } from '$lib/server/time-clock/body';
import { timesheetWriteError } from '$lib/server/time-clock/errors';
import { requireTimesheetWriter } from '$lib/server/time-clock/timesheets';

// Clock out, or stop a forgotten timer at the time work really ended (plan § Forgotten timers). Nothing sent
// means now. Allowed to someone who can correct that person's hours; nothing resumes afterwards.
export const POST: RequestHandler = async (event) => {
	const check = await requireTimesheetWriter(event);
	if ('response' in check) return check.response;

	const body = await readTimesheetBody(event.request, stopTimerAtSchema);
	if ('response' in body) return body.response;

	const { data, error } = await event.locals.supabase.rpc('stop_timer_at', {
		target_organization_id: check.auth.organization.id,
		target_user_id: event.params.userId,
		end_day: body.data.day,
		end_time: body.data.time
	});
	if (error) return timesheetWriteError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
