import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	linkedEntityBelongsToOrganization,
	requireLinkedEntityAccess
} from '$lib/server/access/collaboration';
import { databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { fileAttachSchema, fileDetachSchema } from '$lib/server/validation/files.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// Reuse: putting Files the organization already has onto one record.
//
// The permission checked here is the record's, not the library's. Attaching a document to a quote is an
// edit of the quote -- which is why a sales member, who holds files.view but never files.manage, can still
// do it, exactly as the Part 2 permission table intends. `requireLinkedEntityAccess` is the same gate the
// record's own notes and attachments already use, so there is one answer to "may this person write here"
// rather than a second copy of it for files.
export const POST: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = fileAttachSchema.safeParse(body);
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

	// Read under the caller's own policies before writing anything. A File this member cannot see must
	// answer "not found" rather than becoming attachable by id alone, and the same read tells a stale
	// selection -- a file a colleague trashed while the picker was open -- from a real one.
	const visible = await event.locals.supabase
		.from('files')
		.select('id')
		.in('id', parsed.data.file_ids)
		.is('trashed_at', null);
	if (visible.error) {
		console.error('Could not read files before attaching them.', visible.error);
		return databaseError();
	}
	const visibleIds = new Set((visible.data ?? []).map((file) => file.id));
	const missing = parsed.data.file_ids.filter((id) => !visibleIds.has(id));
	if (visibleIds.size === 0) {
		return json({ error: 'Those files could not be found.' }, { status: 404 });
	}

	const owner = getOwnerSupabaseClient();
	const attached: string[] = [];
	const refused: { file_id: string; reason: string }[] = missing.map((id) => ({
		file_id: id,
		reason: 'That file could not be found.'
	}));

	// One at a time, because each attach is its own decision: a picker selection where one file is still
	// being checked should attach the other four and say which one did not, rather than failing the batch.
	for (const fileId of parsed.data.file_ids) {
		if (!visibleIds.has(fileId)) continue;
		const { error } = await owner.rpc('attach_file_to_record', {
			target_organization_id: organizationId,
			target_file_id: fileId,
			target_actor_id: access.auth.user.id,
			target_entity_type: parsed.data.entity_type,
			target_entity_id: parsed.data.entity_id
		});
		if (!error) {
			attached.push(fileId);
			continue;
		}
		// P0002 is the file itself being gone, 23514 the check that it has passed its scan. Both carry a
		// sentence written for the contractor; anything else is ours to log and answer generically.
		if (error.code === 'P0002' || error.code === '23514') {
			refused.push({ file_id: fileId, reason: error.message });
			continue;
		}
		console.error('Could not attach a file to a record.', error);
		return databaseError();
	}

	return json({ attached_count: attached.length, attached, refused }, { status: 201 });
};

// The other half of reuse: taking one File off one record without touching the File or its other uses.
//
// The permission is the record's again, for the same reason attaching uses it -- removing a document from a
// quote is an edit of the quote. It deliberately does not ask for `files.trash`: that permission governs the
// library's own bin, and a sales member who may edit the quote may also undo a file they just put on it.
export const DELETE: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = fileDetachSchema.safeParse(body);
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

	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner.rpc('detach_file_from_record', {
		target_organization_id: organizationId,
		target_file_id: parsed.data.file_id,
		target_actor_id: access.auth.user.id,
		target_entity_type: parsed.data.entity_type,
		target_entity_id: parsed.data.entity_id
	});

	if (error) {
		// 23503 is the protected-history trigger: this file is part of something the customer already
		// received. Its message is written for the contractor, so it is passed straight through.
		if (error.code === '23503') return json({ error: error.message }, { status: 409 });
		console.error('Could not take a file off a record.', error);
		return databaseError();
	}

	// `false` means the link had already gone -- a colleague removed it, or the button was pressed twice.
	// The caller asked for it not to be there, and it is not, so that is a success with nothing removed.
	return json({ removed: data === true });
};
