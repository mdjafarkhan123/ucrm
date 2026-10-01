import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { placeOpportunitySchema } from '$lib/server/validation/pipeline.schema';

const NOT_FOUND = 'That opportunity could not be found.';

// The short Undo the board offers straight after placing a card in a custom follow-up stage, or taking
// it out of one. The body names the placement being taken back — where the card is now — and
// `pipeline_undo_placement` is the whole gate: that placement must have been made by this same person in
// the last two minutes and still be the last thing that happened to the card. It puts the card back
// where it was with the time it had already spent there. Its refusal is already written for a person, so
// this route only turns it into the right HTTP answer.
export const POST: RequestHandler = async (event) => {
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

	const { data, error } = await event.locals.supabase.rpc('pipeline_undo_placement', {
		target_opportunity_id: event.params.id,
		undone_to_custom_stage_id: parsed.data.custom_stage_id
	});

	if (error) {
		if (error.code === '42501') return notFound(NOT_FOUND);
		if (error.code === '23514') {
			return validationError({ form: error.message ?? 'That move cannot be undone.' });
		}
		return databaseError();
	}

	const result = data as { stage: string; custom_stage_id: string | null };
	return json(
		{ id: event.params.id, stage: result.stage, custom_stage_id: result.custom_stage_id },
		{ headers: NO_STORE_HEADERS }
	);
};
