import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	approveTimesheetsSchema,
	timesheetApprovalQuerySchema
} from '$lib/server/validation/time-clock.schema';
import { readTimesheetBody } from '$lib/server/time-clock/body';
import { timesheetWriteError } from '$lib/server/time-clock/errors';
import { requireTimesheetReader } from '$lib/server/time-clock/timesheets';

function refused() {
	return json(
		{
			error: 'Only someone who manages the team’s time can approve hours.',
			reason: 'permission_denied'
		},
		{ status: 403, headers: NO_STORE_HEADERS }
	);
}

// Weekly approval (docs/time-clock-behavior-contract.md § Weekly approval), for whoever manages the team's
// time. GET reads what approving up to a day would cover: each person's unapproved hours, and the timers still
// running. POST approves; running timers are never approved and come back so they can be stopped first.
export const GET: RequestHandler = async (event) => {
	const check = await requireTimesheetReader(event);
	if ('response' in check) return check.response;
	if (!check.teamVisible) return refused();

	const parsed = timesheetApprovalQuerySchema.safeParse({
		date: event.url.searchParams.get('date') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('timesheet_approval', {
		target_organization_id: check.auth.organization.id,
		cutoff: parsed.data.date
	});
	if (error) return timesheetWriteError(error);

	return json(data, { headers: PRIVATE_READ_HEADERS });
};

export const POST: RequestHandler = async (event) => {
	const check = await requireTimesheetReader(event);
	if ('response' in check) return check.response;
	if (!check.teamVisible) return refused();

	const body = await readTimesheetBody(event.request, approveTimesheetsSchema);
	if ('response' in body) return body.response;

	const { data, error } = await event.locals.supabase.rpc('approve_time_entries', {
		target_organization_id: check.auth.organization.id,
		cutoff: body.data.cutoff,
		target_user_ids: body.data.user_ids
	});
	if (error) return timesheetWriteError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
