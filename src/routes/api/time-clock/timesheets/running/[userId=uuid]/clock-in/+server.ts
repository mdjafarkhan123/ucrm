import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { refuseTimerCommandBody } from '$lib/server/time-clock/body';
import { timesheetWriteError } from '$lib/server/time-clock/errors';
import { requireTimesheetReader } from '$lib/server/time-clock/timesheets';

// A manager clocks a team member in (plan § Timesheets page, Manager actions). `clock_in_member` needs
// time.track_team; the body carries nothing.
export const POST: RequestHandler = async (event) => {
	const check = await requireTimesheetReader(event);
	if ('response' in check) return check.response;
	if (!check.teamVisible)
		return json(
			{ error: 'You do not have access to clock team members in.', reason: 'permission_denied' },
			{ status: 403, headers: NO_STORE_HEADERS }
		);

	const refused = await refuseTimerCommandBody(event.request);
	if (refused) return refused;

	const { data, error } = await event.locals.supabase.rpc('clock_in_member', {
		target_organization_id: check.auth.organization.id,
		target_user_id: event.params.userId
	});
	if (error) return timesheetWriteError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
