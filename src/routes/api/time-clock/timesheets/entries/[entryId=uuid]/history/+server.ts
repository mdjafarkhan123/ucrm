import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { timesheetWriteError } from '$lib/server/time-clock/errors';
import { requireTimesheetReader } from '$lib/server/time-clock/timesheets';

// An entry's edit history (plan § Timesheets page): who added, stopped, changed or removed it, when, and the
// values before and after. Readable by whoever may see the entry; anyone else is told it does not exist.
export const GET: RequestHandler = async (event) => {
	const check = await requireTimesheetReader(event);
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('time_entry_history', {
		target_organization_id: check.auth.organization.id,
		target_entry_id: event.params.entryId
	});
	if (error) return timesheetWriteError(error);

	return json(data, { headers: PRIVATE_READ_HEADERS });
};
