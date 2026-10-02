import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	PRIVATE_READ_HEADERS,
	NO_STORE_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { callLogInputSchema } from '$lib/server/validation/pipeline.schema';
import {
	CALL_LOG_COLUMNS,
	CALL_LOG_LIMIT,
	callWriteError,
	toCallLog,
	type CallLogRow
} from '$lib/server/pipeline/calls';

// The calls a person chose to log on this card, newest first. Bounded by the limit, served by the
// (organization, card, newest) index, so it never grows with the card's age.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase
		.from('opportunity_call_logs')
		.select(CALL_LOG_COLUMNS)
		.eq('organization_id', check.auth.organization.id)
		.eq('opportunity_id', event.params.id)
		.order('created_at', { ascending: false })
		.limit(CALL_LOG_LIMIT);

	if (error) return databaseError();

	return json(
		{ calls: ((data ?? []) as CallLogRow[]).map(toCallLog) },
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Logging a call. Opening the dialler never reaches this -- only a person choosing an outcome does.
// Whether the outcome restarts the card's inactivity clock is decided in the database function, in the same
// write, so the history row and the clock can never disagree.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = callLogInputSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('pipeline_log_opportunity_call', {
		target_opportunity_id: event.params.id,
		new_outcome: parsed.data.outcome,
		new_note: parsed.data.note
	});

	if (error) return callWriteError(error);

	const created = (data as (CallLogRow & { restarted_progress: boolean })[] | null)?.[0];
	if (!created) return callWriteError({ code: '42501' });

	return json(
		{ ...toCallLog(created), restarted_progress: created.restarted_progress },
		{ status: 201, headers: NO_STORE_HEADERS }
	);
};
