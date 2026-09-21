import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Taking one File back out of Trash, into the folder it was in. It does not come back attached to the
// records it was detached from -- the confirmation that trashed it said so, and re-attaching is the record's
// own decision to make again.
export const POST: RequestHandler = async (event) => {
	const fileId = event.params.id;
	if (!/^[0-9a-f-]{36}$/i.test(fileId)) return validationError({ id: 'That file was not found.' });

	const access = await requireOrganizationPermission(event, 'files.trash');
	if ('response' in access) return access.response;

	const { data, error } = await getOwnerSupabaseClient().rpc('restore_file', {
		target_organization_id: access.auth.organization.id,
		target_file_id: fileId,
		target_actor_id: access.auth.user.id
	});
	if (error) {
		if (error.code === 'P0002')
			return json({ error: 'That file is not in Trash.' }, { status: 404 });
		console.error('Could not restore a file.', error);
		return databaseError();
	}

	return json({ file: data });
};
