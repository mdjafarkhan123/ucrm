import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { createFileShareToken, fileShareUrl } from '$lib/server/files/share-links';
import { fileShareCreateSchema } from '$lib/server/validation/files.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// Making one customer file share (behavior contract, "How a selected-file share works"). The token is made
// here, in Node, and the database is handed only its SHA-256, so the raw link exists exactly once: in this
// response, for the Copy link button.
export const POST: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = fileShareCreateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const access = await requireOrganizationPermission(event, 'files.share');
	if ('response' in access) return access.response;

	// Read under the caller's own policies: a share must not become a way to reach a Client or a File this
	// member could not otherwise see. Hidden and missing answer the same "not found".
	const [clientResult, filesResult] = await Promise.all([
		event.locals.supabase
			.from('clients')
			.select('id')
			.eq('id', parsed.data.client_id)
			.maybeSingle(),
		event.locals.supabase.from('files').select('id').in('id', parsed.data.file_ids)
	]);
	if (clientResult.error || filesResult.error) {
		console.error('Could not check a file share before making it.', {
			client: clientResult.error,
			files: filesResult.error
		});
		return databaseError();
	}
	if (!clientResult.data) return validationError({ client_id: 'That client was not found.' });
	if ((filesResult.data ?? []).length !== parsed.data.file_ids.length)
		return validationError({ file_ids: 'One of those files was not found.' });

	const { token, tokenHash } = createFileShareToken();
	const { data, error } = await getOwnerSupabaseClient().rpc('create_file_share', {
		target_organization_id: access.auth.organization.id,
		target_actor_id: access.auth.user.id,
		target_client_id: parsed.data.client_id,
		target_file_ids: parsed.data.file_ids,
		target_days: parsed.data.days,
		supplied_token_hash: tokenHash
	});
	if (error) {
		if (error.code === 'P0409') return validationError({ file_ids: error.message });
		if (error.code === 'P0002') return validationError({ client_id: 'That client was not found.' });
		console.error('Could not make a file share.', { code: error.code, message: error.message });
		return databaseError();
	}

	return json(
		{ share: data, url: fileShareUrl(event.url.origin, token) },
		{ status: 201, headers: NO_STORE_HEADERS }
	);
};
