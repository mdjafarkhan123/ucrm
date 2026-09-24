import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { fileLabelSchema } from '$lib/server/validation/files.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const UUID = /^[0-9a-f-]{36}$/i;

// Renaming a label renames it on every photo that carries it, since photos point at the label rather than
// copying its name.
export const PATCH: RequestHandler = async (event) => {
	const labelId = event.params.id;
	if (!UUID.test(labelId)) return validationError({ id: 'That label was not found.' });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = fileLabelSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const access = await requireOrganizationPermission(event, 'files.manage');
	if ('response' in access) return access.response;

	const { data, error } = await getOwnerSupabaseClient().rpc('rename_file_label', {
		target_organization_id: access.auth.organization.id,
		target_label_id: labelId,
		target_actor_id: access.auth.user.id,
		target_name: parsed.data.name
	});
	if (error) {
		if (error.code === 'P0002')
			return json({ error: 'That label was not found.' }, { status: 404 });
		if (error.code === '23505')
			return validationError({ name: 'You already have a label with that name.' });
		console.error('Could not rename a file label.', error);
		return databaseError();
	}

	return json({ label: { id: data.id, name: data.name } });
};

// Removing a label takes it off every photo that has it. The photos themselves stay exactly as they were.
export const DELETE: RequestHandler = async (event) => {
	const labelId = event.params.id;
	if (!UUID.test(labelId)) return validationError({ id: 'That label was not found.' });

	const access = await requireOrganizationPermission(event, 'files.manage');
	if ('response' in access) return access.response;

	const { error } = await getOwnerSupabaseClient().rpc('delete_file_label', {
		target_organization_id: access.auth.organization.id,
		target_label_id: labelId,
		target_actor_id: access.auth.user.id
	});
	if (error) {
		if (error.code === 'P0002')
			return json({ error: 'That label was not found.' }, { status: 404 });
		console.error('Could not delete a file label.', error);
		return databaseError();
	}

	return new Response(null, { status: 204 });
};
