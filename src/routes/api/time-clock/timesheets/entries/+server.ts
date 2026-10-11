import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { timesheetEntriesQuerySchema } from '$lib/server/validation/time-clock.schema';
import { requireTimesheetReader } from '$lib/server/time-clock/timesheets';

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
