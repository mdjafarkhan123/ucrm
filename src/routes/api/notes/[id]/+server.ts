import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireLinkedEntityAccess } from '$lib/server/access/collaboration';
import { databaseError, validationError } from '$lib/server/api/errors';
import {
	noteUpdateRequestSchema,
	noteUnlinkRequestSchema
} from '$lib/server/validation/collaboration.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

export const PATCH: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = noteUpdateRequestSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const access = await requireLinkedEntityAccess(event, parsed.data.entity_type, 'manage');
	if ('response' in access) return access.response;

	const { data: link } = await event.locals.supabase
		.from('note_links')
		.select('note_id')
		.eq('note_id', event.params.id)
		.eq('entity_type', parsed.data.entity_type)
		.eq('entity_id', parsed.data.entity_id)
		.maybeSingle();
	if (!link) return json({ error: 'That note was not found.' }, { status: 404 });

	const { data, error } = await event.locals.supabase
		.from('notes')
		.update({
			...(parsed.data.body !== undefined
				? { body: parsed.data.body, edited_by: access.auth.user.id, edited_at: new Date().toISOString() }
				: {}),
			...(parsed.data.pinned !== undefined ? { pinned: parsed.data.pinned } : {})
		})
		.eq('id', event.params.id)
		.select()
		.single();
	if (error) return databaseError();

	return json({ note: data });
};

export const DELETE: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = noteUnlinkRequestSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const access = await requireLinkedEntityAccess(event, parsed.data.entity_type, 'manage');
	if ('response' in access) return access.response;

	const { data: deletedLinks, error: unlinkError } = await event.locals.supabase
		.from('note_links')
		.delete()
		.eq('note_id', event.params.id)
		.eq('entity_type', parsed.data.entity_type)
		.eq('entity_id', parsed.data.entity_id)
		.select('id');
	if (unlinkError) return databaseError();
	if (!deletedLinks || deletedLinks.length === 0)
		return json({ error: 'That note was not found.' }, { status: 404 });

	const { data: remainingLinks, error: remainingError } = await event.locals.supabase
		.from('note_links')
		.select('id')
		.eq('note_id', event.params.id);
	if (remainingError) return databaseError();

	let noteDeleted = false;
	if (!remainingLinks || remainingLinks.length === 0) {
		const { error: deleteNoteError } = await event.locals.supabase
			.from('notes')
			.delete()
			.eq('id', event.params.id);
		if (deleteNoteError) return databaseError();
		noteDeleted = true;
	}

	return json({ unlinked: true, note_deleted: noteDeleted });
};
