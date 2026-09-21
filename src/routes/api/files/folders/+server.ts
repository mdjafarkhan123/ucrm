import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { fileFolderCreateSchema } from '$lib/server/validation/files.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// The flat folder list for the left rail, with how many live files sit in each. Folders are a display
// grouping only -- moving a file between them changes no attachment -- so the whole list comes back at
// once rather than being paged.
export const GET: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'files.view');
	if ('response' in access) return access.response;

	const { data, error } = await event.locals.supabase.rpc('list_file_folders', {
		target_organization_id: access.auth.organization.id
	});
	if (error) {
		console.error('Could not list file folders.', error);
		return databaseError();
	}

	return json({ folders: data ?? [] }, { headers: PRIVATE_READ_HEADERS });
};

// One new folder. Flat by design -- the contract asks for optional user folders, not a tree -- so there is
// no parent to name.
export const POST: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = fileFolderCreateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const access = await requireOrganizationPermission(event, 'files.manage');
	if ('response' in access) return access.response;

	const { data, error } = await getOwnerSupabaseClient().rpc('create_file_folder', {
		target_organization_id: access.auth.organization.id,
		target_created_by: access.auth.user.id,
		target_name: parsed.data.name
	});
	if (error) {
		// Folder names are compared without case or surrounding spaces, so this is a real duplicate rather
		// than a near miss. It is the contractor's to fix, not a fault.
		if (error.code === '23505')
			return validationError({ name: 'You already have a folder with that name.' });
		console.error('Could not create a file folder.', error);
		return databaseError();
	}

	return json({ folder: data }, { status: 201 });
};
