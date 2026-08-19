import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { assignOpportunityOwnerSchema } from '$lib/server/validation/pipeline.schema';

const NOT_FOUND = 'That opportunity could not be found.';

// The card's ownership action: assign, reassign, or clear the salesperson.
// `pipeline_update_opportunity_details` (20260818232309) is the one write path onto `opportunities`
// (20260818233632 revokes every other one), so this route only shapes the request and turns the
// function's two refusals into the right HTTP answer.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = assignOpportunityOwnerSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('pipeline_update_opportunity_details', {
		target_opportunity_id: event.params.id,
		set_owner: true,
		new_owner_user_id: parsed.data.owner_user_id
	});

	if (error) {
		// check_violation (23514) is the owner-eligibility trigger's own refusal, worth naming. Every other
		// failure — including a stranger probing another tenant's id, which the function answers with the
		// same insufficient_privilege (42501) either way — gets the same generic not-found.
		if (error.code === '23514') return validationError({ owner_user_id: error.message });
		if (error.code === '42501') return notFound(NOT_FOUND);
		return databaseError();
	}

	const updated = data?.[0];
	if (!updated) return notFound(NOT_FOUND);

	return json(
		{ id: updated.id, owner_user_id: updated.owner_user_id },
		{ headers: NO_STORE_HEADERS }
	);
};
