import { isRedirect, json, redirect } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, validationError } from '$lib/server/api/errors';
import { createPresignedDownloadUrl, getObjectStream } from '$lib/server/storage/r2';

const UUID = /^[0-9a-f-]{36}$/i;

// A photo or file on one of this card's Notes, as the Brief shows it. The Brief is authorized by
// pipeline.view, not by the Request's or Client's own view right, so the File is found through the card
// (`pipeline_opportunity_note_file`) instead of through the File Manager's record-based policy.
//
// `?size=thumb` shows the 480px copy, no option shows the picture itself, and `?download=1` hands any file
// over as a short-lived download link. Only pictures are ever shown inline -- the same rule as
// /api/files/[id]/view -- so an upload can never run as a page on the app's own domain.
export const GET: RequestHandler = async (event) => {
	if (!UUID.test(event.params.id) || !UUID.test(event.params.fileId))
		return validationError({ id: 'That file was not found.' });

	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('pipeline_opportunity_note_file', {
		target_opportunity_id: event.params.id,
		target_file_id: event.params.fileId
	});
	if (error?.code === '42501') return json({ error: 'That file was not found.' }, { status: 404 });
	if (error) return databaseError();

	const file = data?.[0];
	if (!file || !file.object_key)
		return json({ error: 'That file was not found.' }, { status: 404 });
	if (file.processing_state !== 'available')
		return json({ error: 'That file is not ready yet.' }, { status: 409 });

	try {
		if (event.url.searchParams.get('download') === '1') {
			const downloadUrl = await createPresignedDownloadUrl(file.object_key, file.display_name);
			redirect(303, downloadUrl);
		}

		if (!file.mime_type.startsWith('image/'))
			return json({ error: 'That file cannot be shown on the page.' }, { status: 415 });

		const wantsThumbnail = event.url.searchParams.get('size') === 'thumb';
		const objectKey =
			wantsThumbnail && file.thumbnail_object_key ? file.thumbnail_object_key : file.object_key;
		const object = await getObjectStream(objectKey);
		return new Response(object.body, {
			headers: {
				'content-type': object.contentType ?? file.mime_type,
				...(object.contentLength ? { 'content-length': String(object.contentLength) } : {}),
				// The key is a fresh uuid and its bytes never change; private so no shared cache keeps a copy.
				'cache-control': 'private, max-age=86400, immutable'
			}
		});
	} catch (failure) {
		if (isRedirect(failure)) throw failure;
		return json(
			{ error: 'File storage is not configured yet. Ask an admin to set up Cloudflare R2.' },
			{ status: 503 }
		);
	}
};
