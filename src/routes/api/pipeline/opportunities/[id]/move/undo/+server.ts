import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { undoMoveSchema } from '$lib/server/validation/pipeline.schema';

const NOT_FOUND = 'That opportunity could not be found.';

// The short Undo the board offers straight after a reversible move. `pipeline_undo_move` is the one write
// path and the whole gate: the move named here must be one of the five reversible ones, made by this
// same person in the last two minutes, and still the last thing that happened to the card. It puts the
// assessment, the Request's status, and the card's two clocks back in one transaction. Its refusal is
// already written for a person, so this route only turns it into the right HTTP answer.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = undoMoveSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('pipeline_undo_move', {
		target_opportunity_id: event.params.id,
		undone_from_stage: parsed.data.from_stage,
		undone_to_stage: parsed.data.to_stage,
		restore_new_request: parsed.data.restore_new_request
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
