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

	// One RPC, not two sequential inserts: if the link insert fails, the note insert rolls back with it
	// instead of leaving an orphaned, unlinked note behind.
	const { data, error } = await event.locals.supabase.rpc('create_note', {
		target_organization_id: organizationId,
		target_entity_type: parsed.data.entity_type,
		target_entity_id: parsed.data.entity_id,
		new_body: parsed.data.body,
		new_pinned: parsed.data.pinned
	});
	if (error) return databaseError();

	const row = (
		data as {
			id: string;
			organization_id: string;
			body: string;
			pinned: boolean;
			created_by: string | null;
			edited_by: string | null;
			edited_at: string | null;
			created_at: string;
			updated_at: string;
			link_id: string;
			entity_type: string;
			entity_id: string;
			link_created_at: string;
		}[]
	)[0];
	if (!row) return databaseError();

	const { link_id, entity_type, entity_id, link_created_at, ...note } = row;
	const link = {
		id: link_id,
		organization_id: note.organization_id,
		note_id: note.id,
		entity_type,
		entity_id,
		created_at: link_created_at
	};

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
