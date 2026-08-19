import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { updateOpportunityNextFollowUpSchema } from '$lib/server/validation/pipeline.schema';

const NOT_FOUND = 'That opportunity could not be found.';

// The Brief's next follow-up date edit. Same one write path and same route shape as the owner and value
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

	const parsed = updateOpportunityNextFollowUpSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('pipeline_update_opportunity_details', {
		target_opportunity_id: event.params.id,
		set_next_follow_up: true,
		new_next_follow_up_on: parsed.data.next_follow_up_on
	});

	if (error) {
		if (error.code === '23514') return validationError({ next_follow_up_on: error.message });
		if (error.code === '42501') return notFound(NOT_FOUND);
		return databaseError();
	}

	const updated = data?.[0];
	if (!updated) return notFound(NOT_FOUND);

	return json(
		{ id: updated.id, next_follow_up_on: updated.next_follow_up_on },
		{ headers: NO_STORE_HEADERS }
	);
};
