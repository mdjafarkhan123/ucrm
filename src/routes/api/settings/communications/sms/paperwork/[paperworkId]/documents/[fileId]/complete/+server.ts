import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { memberActorLabel } from '$lib/server/setup/protected-documents';

// Step two of adding a paperwork file: the browser reports that the bytes reached storage. Only the person
// who started the upload can finish it; this only puts the file in the virus check's queue.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;
	const paperworkId = z.uuid().safeParse(event.params.paperworkId);
	const fileId = z.uuid().safeParse(event.params.fileId);
	if (!paperworkId.success || !fileId.success)
		return validationError({ id: 'That file was not found.' });

	const client = getOwnerSupabaseClient();
	const { data: held, error: heldError } = await client
		.from('communication_sms_number_paperwork_documents')
		.select('id')
		.eq('organization_id', check.auth.organization.id)
		.eq('paperwork_id', paperworkId.data)
		.eq('protected_document_id', fileId.data)
		.maybeSingle();
	if (heldError) return databaseError();
	if (!held) return validationError({ id: 'That file was not found.' });

	const { error } = await client.rpc('complete_setup_protected_document', {
		target_document_id: fileId.data,
		target_organization_id: check.auth.organization.id,
		target_uploaded_by: check.auth.user.id,
		target_actor_label: await memberActorLabel(check.auth.user.id, check.auth.user.email)
	});
	if (error) {
		if (error.code === 'P0002')
			return validationError({ id: 'That upload is not waiting to be finished.' });
		console.error('Could not finish a paperwork file upload.', error);
		return databaseError();
	}
	return json({ completed: true }, { headers: NO_STORE_HEADERS });
};
