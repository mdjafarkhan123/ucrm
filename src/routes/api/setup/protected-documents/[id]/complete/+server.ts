import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { requireSetupEditor } from '$lib/server/setup/access';
import { memberActorLabel } from '$lib/server/setup/protected-documents';

// Client onboarding B9a, step two: the browser reports that the bytes reached storage. Only the person who
// started the upload can finish it, and finishing records them in the document's history. The bytes are not
// trusted for it: this only puts the document in the virus check's queue.
export const POST: RequestHandler = async (event) => {
	const check = await requireSetupEditor(event);
	if ('response' in check) return check.response;

	const id = z.uuid().safeParse(event.params.id);
	if (!id.success) return validationError({ id: 'That file was not found.' });

	const { error } = await getOwnerSupabaseClient().rpc('complete_setup_protected_document', {
		target_document_id: id.data,
		target_organization_id: check.auth.organization.id,
		target_uploaded_by: check.auth.user.id,
		target_actor_label: await memberActorLabel(check.auth.user.id, check.auth.user.email)
	});
	if (error) {
		if (error.code === 'P0002')
			return validationError({ id: 'That upload is not waiting to be finished.' });
		console.error('Could not finish a protected setup document upload.', error);
		return databaseError();
	}
	return json({ completed: true }, { headers: NO_STORE_HEADERS });
};
