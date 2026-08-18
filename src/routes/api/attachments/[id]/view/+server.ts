import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	requireLinkedEntityAccess,
	type LinkedEntityType
} from '$lib/server/access/collaboration';
import { databaseError } from '$lib/server/api/errors';
import { getObjectStream } from '$lib/server/storage/r2';

// Shows a photo on the page, as opposed to `/download` which hands the office a file to keep. A presigned
// link cannot do this job: it dies after five minutes, so every image on a page left open would break.
// Streaming through here also means an `<img>` needs no fetch, no token, and no refresh — just a URL.
//
// Images only. Serving arbitrary uploads inline from our own origin is how a file turns into a way to run
// code on the app's domain; anything that is not an image goes out through `/download` as a file instead.
const VIEWABLE_MIME_PREFIX = 'image/';

export const GET: RequestHandler = async (event) => {
	const { data: attachment, error: lookupError } = await event.locals.supabase
		.from('attachments')
		.select('id, entity_type, object_key, thumbnail_object_key, mime_type')
		.eq('id', event.params.id)
		.maybeSingle();
	if (lookupError) return databaseError();
	if (!attachment) return json({ error: 'That file was not found.' }, { status: 404 });

	if (!attachment.mime_type.startsWith(VIEWABLE_MIME_PREFIX))
		return json({ error: 'That file cannot be shown on the page.' }, { status: 415 });

	const entityType = attachment.entity_type as LinkedEntityType;
	const access = await requireLinkedEntityAccess(event, entityType, 'view');
	if ('response' in access) return access.response;

	// The small copy for a grid or filmstrip, the original for the big view. An image with no small copy —
	// uploaded before thumbnails existed, or one the browser could not decode — falls back to the original.
	const wantsThumbnail = event.url.searchParams.get('size') === 'thumb';
	const objectKey =
		wantsThumbnail && attachment.thumbnail_object_key
			? attachment.thumbnail_object_key
			: attachment.object_key;

	try {
		const object = await getObjectStream(objectKey);
		return new Response(object.body, {
			headers: {
				'content-type': object.contentType ?? attachment.mime_type,
				...(object.contentLength ? { 'content-length': String(object.contentLength) } : {}),
				// Object keys carry a fresh uuid, so a key never points at different bytes later. Private
				// because the permission check above is the only thing standing between this and another
				// organization's photos — no shared cache may keep a copy.
				'cache-control': 'private, max-age=86400, immutable'
			}
		});
	} catch {
		return json(
			{ error: 'File storage is not configured yet. Ask an admin to set up Cloudflare R2.' },
			{ status: 503 }
		);
	}
};
