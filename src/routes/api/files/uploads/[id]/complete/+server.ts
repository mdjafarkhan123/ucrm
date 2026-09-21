import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Step two: the browser reports that the bytes reached storage. That is all this does -- it makes the File
// claimable by the processing worker. The upload is not trusted because the browser says so; saying so is
// only what tells us there is now something to check.
export const POST: RequestHandler = async (event) => {
	const fileId = event.params.id;
	if (!/^[0-9a-f-]{36}$/i.test(fileId)) return validationError({ id: 'That file was not found.' });

	const access = await requireOrganizationPermission(event, 'files.manage');
	if ('response' in access) return access.response;

	// Tenant, uploader and current state are all re-checked inside complete_file_upload, so a caller
	// cannot finish someone else's upload or revive a file that already failed.
	const { data, error } = await getOwnerSupabaseClient().rpc('complete_file_upload', {
		target_file_id: fileId,
		target_organization_id: access.auth.organization.id,
		target_uploaded_by: access.auth.user.id
	});
	if (error) {
		// The function raises no_data_found when nothing matched, which is the ordinary "not yours, not
		// waiting, or already finished" case rather than a fault.
		if (error.code === 'P0002' || /not waiting to be finished/.test(error.message))
			return validationError({ id: 'That upload is not waiting to be finished.' });
		console.error('Could not complete a file upload.', error);
		return databaseError();
	}

	return json({ file: data });
};
