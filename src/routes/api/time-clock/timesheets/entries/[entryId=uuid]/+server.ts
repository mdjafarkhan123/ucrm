import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { timesheetEntrySchema } from '$lib/server/validation/time-clock.schema';
import { readTimesheetBody } from '$lib/server/time-clock/body';
import { timesheetWriteError } from '$lib/server/time-clock/errors';
import { requireTimesheetReader } from '$lib/server/time-clock/timesheets';

function refused() {
	return json(
		{ error: 'You do not have access to these hours.', reason: 'permission_denied' },
		{ status: 403, headers: NO_STORE_HEADERS }
	);
}

// Correcting an entry (plan § Timesheets page): the person, what it was for, the day, times and notes. The
// command checks the reader may change the hours as they are and as they become, refuses a running timer, and
// writes the before and after to the edit history (and to Job costing for Job hours).
export const PATCH: RequestHandler = async (event) => {
	const check = await requireTimesheetReader(event);
	if ('response' in check) return check.response;

	const body = await readTimesheetBody(event.request, timesheetEntrySchema);
	if ('response' in body) return body.response;
	if (!check.teamVisible && body.data.user_id !== check.auth.user.id) return refused();

	const { data, error } = await event.locals.supabase.rpc('update_time_entry', {
		target_organization_id: check.auth.organization.id,
		target_entry_id: event.params.entryId,
		target_user_id: body.data.user_id,
		// The generated types cannot say these may be null: no Job means General time, with no visit.
		target_job_id: body.data.job_id as string,
		target_visit_id: body.data.visit_id as string,
		work_day: body.data.day,
		start_time: body.data.start_time,
		end_time: body.data.end_time,
		notes: body.data.notes ?? undefined
	});
	if (error) return timesheetWriteError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};

// Removing an entry. A running timer cannot be deleted; it has to be stopped first.
export const DELETE: RequestHandler = async (event) => {
	const check = await requireTimesheetReader(event);
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('delete_time_entry', {
		target_organization_id: check.auth.organization.id,
		target_entry_id: event.params.entryId
	});
	if (error) return timesheetWriteError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
