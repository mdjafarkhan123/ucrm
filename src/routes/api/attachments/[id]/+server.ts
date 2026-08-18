import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	requireLinkedEntityAccess,
	type LinkedEntityType
} from '$lib/server/access/collaboration';
import { databaseError } from '$lib/server/api/errors';
import { deleteObject } from '$lib/server/storage/r2';

export const DELETE: RequestHandler = async (event) => {
	const { data: attachment, error: lookupError } = await event.locals.supabase
		.from('attachments')
		.select('id, entity_type, object_key, thumbnail_object_key')
		.eq('id', event.params.id)
		.maybeSingle();
	if (lookupError) return databaseError();
	if (!attachment) return json({ error: 'That file was not found.' }, { status: 404 });

	const entityType = attachment.entity_type as LinkedEntityType;
	const access = await requireLinkedEntityAccess(event, entityType, 'manage');
	if ('response' in access) return access.response;

	const { error } = await event.locals.supabase
		.from('attachments')
		.delete()
		.eq('id', attachment.id);
	if (error) return databaseError();

	// A photo's small preview goes with it, or it would sit in the bucket forever with nothing pointing at
	// it. Both are best-effort: the database row (the tenant-isolation boundary) is already gone, so a
	// storage failure here is logged, not surfaced as a failed delete.
	const objectKeys = [attachment.object_key, attachment.thumbnail_object_key].filter(
		(key): key is string => Boolean(key)
	);
	for (const objectKey of objectKeys) {
		try {
			await deleteObject(objectKey);
		} catch (storageError) {
			console.error('Could not delete R2 object for attachment.', attachment.id, storageError);
		}
	}

	return json({ deleted: true });
};
