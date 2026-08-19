import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { pipelineNoteCreateSchema } from '$lib/server/validation/pipeline.schema';
import { pipelineNoteWriteError, type PipelineNoteRow } from '$lib/server/pipeline/notes';

// The Brief's Notes, pooled from the opportunity's Request and Client in one answer. Authorized by
// pipeline.view/pipeline.edit, not by customers.view/customers.edit -- the RPCs re-check this permission
// themselves and resolve the Request/Client ids from the Opportunity row, so this route's own check is a
// cheap early exit, not the security boundary.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('pipeline_opportunity_notes', {
		target_opportunity_id: event.params.id
	});

	if (error) return pipelineNoteWriteError(error);

	return json({ notes: (data ?? []) as PipelineNoteRow[] }, { headers: PRIVATE_READ_HEADERS });
};

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = pipelineNoteCreateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('pipeline_create_opportunity_note', {
		target_opportunity_id: event.params.id,
		target_entity_type: parsed.data.entity_type,
		new_body: parsed.data.body
	});

	if (error) return pipelineNoteWriteError(error);

	const created = (data as PipelineNoteRow[] | null)?.[0];
	if (!created) return databaseError();

	return json({ note: created }, { status: 201, headers: NO_STORE_HEADERS });
};
