import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	pipelineNoteEntityTypeSchema,
	pipelineNoteUpdateSchema
} from '$lib/server/validation/pipeline.schema';
import {
	pipelineNoteNotFound,
	pipelineNoteWriteError,
	type PipelineNoteRow
} from '$lib/server/pipeline/notes';

// A Brief Note lives under its Opportunity in the URL, unlike a Task: the write functions must be told
// which Opportunity the caller means, so they can confirm the note is actually on that Opportunity's
// Request or Client rather than trusting the note id alone.

export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = pipelineNoteUpdateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('pipeline_update_opportunity_note', {
		target_note_id: event.params.noteId,
		target_opportunity_id: event.params.id,
		new_body: parsed.data.body
	});

	if (error) return pipelineNoteWriteError(error);

	const updated = (data as PipelineNoteRow[] | null)?.[0];
	if (!updated) return pipelineNoteNotFound();

	return json({ note: updated }, { headers: NO_STORE_HEADERS });
};

export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = pipelineNoteEntityTypeSchema.safeParse(
		body && (body as { entity_type?: unknown }).entity_type
	);
	if (!parsed.success) return validationError({ entity_type: 'Choose which target to remove.' });

	const { data, error } = await event.locals.supabase.rpc('pipeline_delete_opportunity_note', {
		target_note_id: event.params.noteId,
		target_opportunity_id: event.params.id,
		target_entity_type: parsed.data
	});

	if (error) return pipelineNoteWriteError(error);

	const deleted = (data as { unlinked: boolean; note_deleted: boolean }[] | null)?.[0];
	if (!deleted) return pipelineNoteNotFound();

	return json(deleted, { headers: NO_STORE_HEADERS });
};
