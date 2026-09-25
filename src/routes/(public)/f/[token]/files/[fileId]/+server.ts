import { error as httpError } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { fileShareTokenHash, resolveFileShare } from '$lib/server/files/share-links';
import { getObjectStream } from '$lib/server/storage/r2';

// One shared File's bytes. The token buys exactly the Files its share names and that are still live (not in
// Trash), so every other id -- including the same business's other files -- is a plain 404. Nothing here is
// a storage URL: the bytes stream through this request, which dies with the link.
//
// `?size=thumb` serves the small picture for the page's tiles; `?download=1` saves the file instead of
// opening it. The saved name is the one the File had when it was shared.
export const GET: RequestHandler = async (event) => {
	const tokenHash = fileShareTokenHash(event.params.token);
	if (!tokenHash) throw httpError(404, 'That file is not available.');

	const share = await resolveFileShare(tokenHash);
	const file =
		share?.state === 'active'
			? share.files.find((candidate) => candidate.id === event.params.fileId)
			: undefined;
	if (!file) throw httpError(404, 'That file is not available.');

	const wantsThumbnail = event.url.searchParams.get('size') === 'thumb';
	const objectKey =
		wantsThumbnail && file.thumbnail_object_key ? file.thumbnail_object_key : file.object_key;
	const disposition = event.url.searchParams.get('download') === '1' ? 'attachment' : 'inline';
	const safeName = file.name.replace(/["\\\r\n]/g, '');

	try {
		const object = await getObjectStream(objectKey);
		return new Response(object.body, {
			headers: {
				'content-type': object.contentType ?? file.mime_type,
				...(object.contentLength ? { 'content-length': String(object.contentLength) } : {}),
				'content-disposition': `${disposition}; filename="${safeName}"; filename*=UTF-8''${encodeURIComponent(file.name)}`,
				'x-content-type-options': 'nosniff',
				'referrer-policy': 'no-referrer',
				'x-robots-tag': 'noindex, nofollow, noarchive',
				// Private, because the token in the URL is the only thing between this and a customer's file.
				'cache-control': 'private, max-age=3600'
			}
		});
	} catch {
		throw httpError(404, 'That file is not available.');
	}
};
