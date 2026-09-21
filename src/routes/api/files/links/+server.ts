import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	linkedEntityBelongsToOrganization,
	requireLinkedEntityAccess
} from '$lib/server/access/collaboration';
import { databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { fileAttachSchema } from '$lib/server/validation/files.schema';
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
