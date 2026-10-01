import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { placeOpportunitySchema } from '$lib/server/validation/pipeline.schema';

const NOT_FOUND = 'That opportunity could not be found.';
// The database's own word for "this on-hold stage wants a follow-up Task first".
const NEEDS_FUTURE_TASK = 'needs_future_task';

// Placing a card in a custom follow-up stage, or putting it back in its real stage with `null`. This is
// follow-up organization only: it never touches the Request, Assessment, or Quote, which is why it is its
// own route rather than another branch of the drag route beside it — that one performs a real domain
// action, this one never does.
//
// `pipeline_place_opportunity` is the one write path and the whole gate: the card is open and on the
// board, the stage is switched on, and the two are in the same section. Its refusals arrive already
// written for a person, so this route only turns them into the right HTTP answer. The one refusal the
// board can do something about -- an on-hold stage wanting a Task with a future date -- is also named in
// `code`, so the board can offer to add that Task instead of only saying no.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = placeOpportunitySchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('pipeline_place_opportunity', {
		target_opportunity_id: event.params.id,
		target_custom_stage_id: parsed.data.custom_stage_id
	});

	if (error) {
		if (error.code === '42501') return notFound(NOT_FOUND);
		if (error.code === '23514') {
			const message = error.message ?? 'That card cannot be moved there.';
			if (error.hint === NEEDS_FUTURE_TASK) {
				return json(
					{ error: message, field_errors: { form: message }, code: NEEDS_FUTURE_TASK },
					{ status: 422, headers: NO_STORE_HEADERS }
				);
			}
			return validationError({ form: message });
		}
		return databaseError();
	}

	return json(
		{
			id: event.params.id,
			stage: data.stage,
			custom_stage_id: data.custom_stage_id,
			// False when the card was already there: nothing changed and no history was written.
			applied: data.applied
		},
		{ headers: NO_STORE_HEADERS }
	);
};
