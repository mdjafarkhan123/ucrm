import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { requireLinkedEntityAccess, type LinkedEntityType } from '$lib/server/access/collaboration';
import { getOrganizationContext, type OrganizationContext } from '$lib/server/auth/organization';
import { databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Letting go of a line photo a save just dropped. Unlike Trash, this never takes a photo away from anything:
// release_line_photo moves it to Trash only when no record, link or share uses it any more, and otherwise
// leaves it alone. So the person who removed it from their own line may ask -- files.trash, or the right to
// edit the record the photo was uploaded from, the same pair /api/files/uploads accepts.
export const POST: RequestHandler = async (event) => {
	const fileId = event.params.id;
	if (!/^[0-9a-f-]{36}$/i.test(fileId)) return validationError({ id: 'That file was not found.' });

	let access: { auth: OrganizationContext } | { response: Response } =
		await requireOrganizationPermission(event, 'files.trash');
	if ('response' in access) {
		const member = await getOrganizationContext(event);
		if (!member) return access.response;
		const { data: file, error } = await getOwnerSupabaseClient()
			.from('files')
			.select('origin_type')
			.eq('organization_id', member.organization.id)
			.eq('id', fileId)
			.maybeSingle();
		if (error) {
			console.error('Could not read a line photo before releasing it.', error);
			return databaseError();
		}
		if (!file?.origin_type) return json({ released: false });
		access = await requireLinkedEntityAccess(event, file.origin_type as LinkedEntityType, 'manage');
		if ('response' in access) return access.response;
	}

	const { data, error } = await getOwnerSupabaseClient().rpc('release_line_photo', {
		target_organization_id: access.auth.organization.id,
		target_file_id: fileId,
		target_actor_id: access.auth.user.id
	});
	if (error) {
		console.error('Could not release a line photo.', error);
		return databaseError();
	}

	return json({ released: data === true });
};
