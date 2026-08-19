import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { updateOpportunityExpectedCloseSchema } from '$lib/server/validation/pipeline.schema';

const NOT_FOUND = 'That opportunity could not be found.';

// The Brief's expected close date edit. Same one write path and same route shape as the owner and value
// routes beside it.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = updateOpportunityExpectedCloseSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('pipeline_update_opportunity_details', {
		target_opportunity_id: event.params.id,
		set_expected_close: true,
		new_expected_close_on: parsed.data.expected_close_on
	});

	if (error) {
		if (error.code === '23514') return validationError({ expected_close_on: error.message });
		if (error.code === '42501') return notFound(NOT_FOUND);
		return databaseError();
	}

	const updated = data?.[0];
	if (!updated) return notFound(NOT_FOUND);

	return json(
		{ id: updated.id, expected_close_on: updated.expected_close_on },
		{ headers: NO_STORE_HEADERS }
	);
};
