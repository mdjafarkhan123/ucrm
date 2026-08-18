import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	requireLinkedEntityAccess,
	type LinkedEntityType
} from '$lib/server/access/collaboration';
import { databaseError } from '$lib/server/api/errors';
import { createPresignedDownloadUrl } from '$lib/server/storage/r2';

export const GET: RequestHandler = async (event) => {
	const { data: attachment, error: lookupError } = await event.locals.supabase
		.from('attachments')
		.select('id, entity_type, entity_id, object_key, file_name')
		.eq('id', event.params.id)
		.maybeSingle();
	if (lookupError) return databaseError();
	if (!attachment) return json({ error: 'That file was not found.' }, { status: 404 });

	const entityType = attachment.entity_type as LinkedEntityType;
	const access = await requireLinkedEntityAccess(event, entityType, 'view');
	if ('response' in access) return access.response;

	try {
		const downloadUrl = await createPresignedDownloadUrl(
			attachment.object_key,
			attachment.file_name
		);
		return json({ download_url: downloadUrl });
	} catch {
		return json(
			{ error: 'File storage is not configured yet. Ask an admin to set up Cloudflare R2.' },
			{ status: 503 }
		);
	}
};
