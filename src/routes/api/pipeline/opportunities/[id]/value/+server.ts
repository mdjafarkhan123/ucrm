import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { updateOpportunityValueSchema } from '$lib/server/validation/pipeline.schema';

const NOT_FOUND = 'That opportunity could not be found.';

// The Brief's estimated value edit. `pipeline_update_opportunity_details` (20260818232309) is the one
// write path onto `opportunities`, so this route only shapes the request and turns the function's two
// refusals into the right HTTP answer — same shape as the owner route beside it.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = updateOpportunityValueSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('pipeline_update_opportunity_details', {
		target_opportunity_id: event.params.id,
		set_value: true,
		new_estimated_value: parsed.data.estimated_value
	});

	if (error) {
		// check_violation (23514) is the database's own `>= 0` guard, worth naming even though the schema
		// above already refuses a negative value first. Every other failure — no edit access, or edit
		// access without permission to see money, which the RPC answers identically — gets the same
		// generic not-found, same as the owner route.
		if (error.code === '23514') return validationError({ estimated_value: error.message });
		if (error.code === '42501') return notFound(NOT_FOUND);
		return databaseError();
	}

	const updated = data?.[0];
	if (!updated) return notFound(NOT_FOUND);

	return json(
		{ id: updated.id, estimated_value: updated.estimated_value },
		{ headers: NO_STORE_HEADERS }
	);
};
