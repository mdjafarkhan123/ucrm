import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { databaseError, validationError } from '$lib/server/api/errors';
import { getObjectStream } from '$lib/server/storage/r2';

// Shows a picture on the page, the way /api/attachments/[id]/view does for the old path. A presigned link
// cannot do this job -- it expires in minutes, so every image in a grid left open would break.
//
// Images only. Serving arbitrary uploads inline from our own origin is how a file turns into a way to run
// code on the app's domain; everything else leaves through /download as a file instead.
const VIEWABLE_MIME_PREFIX = 'image/';

export const GET: RequestHandler = async (event) => {
	const fileId = event.params.id;
	if (!/^[0-9a-f-]{36}$/i.test(fileId)) return validationError({ id: 'That file was not found.' });

	const auth = await getOrganizationContext(event);
	if (!auth)
		return json({ error: 'Authentication or organization membership required.' }, { status: 401 });

	// The row itself is the permission check: the Part 2 policy only returns a file this reader may see,
	// through the library permission or through a record they can already open.
	const { data: file, error } = await event.locals.supabase
		.from('files')
		.select('id, mime_type, object_key, thumbnail_object_key, processing_state, trashed_at')
		.eq('id', fileId)
		.maybeSingle();
	if (error) return databaseError();
	if (!file) return json({ error: 'That file was not found.' }, { status: 404 });

	// Nothing unverified is ever shown. A pending file's bytes have not been scanned yet, and a quarantined
	// one failed the scan; its uploader can still see the row and its progress, never its content.
	if (file.processing_state !== 'available')
		return json({ error: 'That file is not ready yet.' }, { status: 409 });

	// A purged File keeps its row (so "removed" keeps showing wherever it was used) but has no bytes left.
	if (!file.object_key) return json({ error: 'That file was not found.' }, { status: 404 });

	if (!file.mime_type.startsWith(VIEWABLE_MIME_PREFIX))
		return json({ error: 'That file cannot be shown on the page.' }, { status: 415 });

	// The 480px copy for a grid, the original for the lightbox. A picture with no small copy -- one the
	// decoder could not read, or a backfilled attachment that never had one -- falls back to the original.
	const wantsThumbnail = event.url.searchParams.get('size') === 'thumb';
	const objectKey =
		wantsThumbnail && file.thumbnail_object_key ? file.thumbnail_object_key : file.object_key;

	try {
		const object = await getObjectStream(objectKey);
		return new Response(object.body, {
			headers: {
				'content-type': object.contentType ?? file.mime_type,
				...(object.contentLength ? { 'content-length': String(object.contentLength) } : {}),
				// A key carries a fresh uuid and its bytes are immutable, so it never points at different
				// content later. Private because the check above is the only thing between this and another
				// organization's photos -- no shared cache may keep a copy.
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
