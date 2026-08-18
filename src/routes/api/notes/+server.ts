import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	requireLinkedEntityAccess,
	linkedEntityBelongsToOrganization,
	parseLinkedEntityQuery
} from '$lib/server/access/collaboration';
import { databaseError, validationError } from '$lib/server/api/errors';
import { noteCreateSchema } from '$lib/server/validation/collaboration.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import type { Tables } from '$lib/database.types';

export const POST: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = noteCreateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const access = await requireLinkedEntityAccess(event, parsed.data.entity_type, 'manage');
	if ('response' in access) return access.response;

	const organizationId = access.auth.organization.id;
	const belongs = await linkedEntityBelongsToOrganization(
		event.locals.supabase,
		organizationId,
		parsed.data.entity_type,
		parsed.data.entity_id
	);
	if (!belongs) return validationError({ entity_id: 'That record was not found.' });

	const { data: note, error: noteError } = await event.locals.supabase
		.from('notes')
		.insert({
			organization_id: organizationId,
			body: parsed.data.body,
			pinned: parsed.data.pinned,
			created_by: access.auth.user.id
		})
		.select()
		.single();
	if (noteError) return databaseError();

	const { data: link, error: linkError } = await event.locals.supabase
		.from('note_links')
		.insert({
			organization_id: organizationId,
			note_id: note.id,
			entity_type: parsed.data.entity_type,
			entity_id: parsed.data.entity_id
		})
		.select()
		.single();
	if (linkError) return databaseError();

	return json({ note: { ...note, links: [link] } }, { status: 201 });
};

export const GET: RequestHandler = async (event) => {
	const params = parseLinkedEntityQuery(event.url);
	if (!params) return validationError({ entity_type: 'Provide entity_type and entity_id.' });

	const access = await requireLinkedEntityAccess(event, params.entity_type, 'view');
	if ('response' in access) return access.response;

	const { data: links, error: linksError } = await event.locals.supabase
		.from('note_links')
		.select('note_id')
		.eq('entity_type', params.entity_type)
		.eq('entity_id', params.entity_id);
	if (linksError) return databaseError();

	const noteIds = [...new Set((links ?? []).map((link) => link.note_id))];
	if (noteIds.length === 0) return json({ notes: [] });

	const [{ data: notes, error: notesError }, { data: allLinks, error: allLinksError }] =
		await Promise.all([
			event.locals.supabase
				.from('notes')
				.select('*')
				.in('id', noteIds)
				.order('pinned', { ascending: false })
				.order('created_at', { ascending: false }),
			event.locals.supabase.from('note_links').select('*').in('note_id', noteIds)
		]);
	if (notesError || allLinksError) return databaseError();

	const linksByNote = new Map<string, Tables<'note_links'>[]>();
	for (const link of allLinks ?? []) {
		const existing = linksByNote.get(link.note_id);
		if (existing) existing.push(link);
		else linksByNote.set(link.note_id, [link]);
	}

	return json({
		notes: (notes ?? []).map((note) => ({ ...note, links: linksByNote.get(note.id) ?? [] }))
	});
};
