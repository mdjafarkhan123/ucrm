import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { timesheetSummaryQuerySchema } from '$lib/server/validation/time-clock.schema';
import { requireTimesheetReader } from '$lib/server/time-clock/timesheets';

// Timesheets (docs/time-clock-behavior-contract.md § Timesheets page): one row per person for a day or a
// week, with a total for each day. Its size grows with the team, never with the entries; a person's entries
// are read separately when their row is opened. Who appears is decided by `timesheet_summary`.
export const GET: RequestHandler = async (event) => {
	const check = await requireTimesheetReader(event);
	if ('response' in check) return check.response;

	const parsed = timesheetSummaryQuerySchema.safeParse({
		span: event.url.searchParams.get('span') ?? undefined,
		date: event.url.searchParams.get('date') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('timesheet_summary', {
		target_organization_id: check.auth.organization.id,
		anchor_date: parsed.data.date,
		span: parsed.data.span
	});
	if (error) {
		if (error.code === '42501') {
			return json(
				{ error: 'You do not have access to do that.', reason: 'permission_denied' },
				{ status: 403 }
			);
		}
		return databaseError();
	}

	return json(data, { headers: PRIVATE_READ_HEADERS });
};
