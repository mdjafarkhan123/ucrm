import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	timesheetEntriesQuerySchema,
	timesheetEntrySchema
} from '$lib/server/validation/time-clock.schema';
import { readTimesheetBody } from '$lib/server/time-clock/body';
import { timesheetWriteError } from '$lib/server/time-clock/errors';
import { requireTimesheetReader, requireTimesheetWriter } from '$lib/server/time-clock/timesheets';

function refused() {
	return json(
		{ error: 'You do not have access to these hours.', reason: 'permission_denied' },
		{ status: 403 }
	);
}

// One person's Timesheets entries for a day or a week, read when their row is opened. Someone limited to
// their own time is refused a teammate's here, before the database says the same (plan § Timesheets page).
export const GET: RequestHandler = async (event) => {
	const check = await requireTimesheetReader(event);
	if ('response' in check) return check.response;

	const parsed = timesheetEntriesQuerySchema.safeParse({
		user_id: event.url.searchParams.get('user_id') ?? undefined,
		from: event.url.searchParams.get('from') ?? undefined,
		to: event.url.searchParams.get('to') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	if (!check.teamVisible && parsed.data.user_id !== check.auth.user.id) return refused();

	const { data, error } = await event.locals.supabase.rpc('timesheet_entries', {
		target_organization_id: check.auth.organization.id,
		target_user_id: parsed.data.user_id,
		range_from: parsed.data.from,
		range_to: parsed.data.to
	});
	if (error) {
		if (error.code === '42501') return refused();
		return databaseError();
	}

	return json(data, { headers: PRIVATE_READ_HEADERS });
};

// Add entry (plan § Timesheets page): a Job (and optionally its visit) or General, a day, start and end times
// and notes. Whose hours they are is checked by `add_time_entry`: anyone's with time.track_team, otherwise
// only the reader's own. Job hours go through the same command as the Job's Labor section.
export const POST: RequestHandler = async (event) => {
	const check = await requireTimesheetWriter(event);
	if ('response' in check) return check.response;

	const body = await readTimesheetBody(event.request, timesheetEntrySchema);
	if ('response' in body) return body.response;
	if (!check.teamVisible && body.data.user_id !== check.auth.user.id) return refused();

	const { data, error } = await event.locals.supabase.rpc('add_time_entry', {
		target_organization_id: check.auth.organization.id,
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

	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};
