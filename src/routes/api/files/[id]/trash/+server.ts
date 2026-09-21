import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Moving one File to Trash. The behavior contract calls this the confirmed action, and it is the only way
// an ordinary link is removed: the File is detached from every record using it, which the dialog said in
// plain words before the contractor pressed the button. A File carrying a use the customer already received
// does not go at all until its owning domain retires that use.
export const POST: RequestHandler = async (event) => {
	const fileId = event.params.id;
	if (!/^[0-9a-f-]{36}$/i.test(fileId)) return validationError({ id: 'That file was not found.' });

	// Its own permission, separate from files.manage: sales and finance browse the library and attach from
	// it, but nobody makes a file disappear from other people's jobs by accident.
	const access = await requireOrganizationPermission(event, 'files.trash');
	if ('response' in access) return access.response;

	const { data, error } = await getOwnerSupabaseClient().rpc('trash_file', {
		target_organization_id: access.auth.organization.id,
		target_file_id: fileId,
		target_actor_id: access.auth.user.id
	});
	if (error) {
		if (error.code === 'P0002') return json({ error: 'That file was not found.' }, { status: 404 });
		// Both guards -- the function's own check and the Part 2 trigger underneath it -- refuse a protected
		// use with the same sentence, and it is written for the contractor to read.
		if (error.code === '23514' || error.code === '23503')
			return json({ error: error.message }, { status: 409 });
		console.error('Could not move a file to Trash.', error);
		return databaseError();
	}

	return json({ file: data });
};
