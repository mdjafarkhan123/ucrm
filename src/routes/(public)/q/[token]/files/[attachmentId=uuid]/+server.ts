import { error as httpError } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	getQuoteAccessResolverClient,
	quoteAccessTokenHash
} from '$lib/server/quotes/access-links';
import { getObjectStream } from '$lib/server/storage/r2';

// Files on the customer's copy. The token buys one document, so it buys exactly the files that document
// names — the attachments marked customer-visible and the photos on its lines. Everything else, including
// the same organization's other files, is a plain 404 here.
//
// There is no shareable storage URL anywhere in this: the bytes are streamed through this request, which
// dies with the link. The staff attachment routes are not reachable without a session and are never
// borrowed for this job.
export const GET: RequestHandler = async (event) => {
	const tokenHash = quoteAccessTokenHash(event.params.token);
	if (!tokenHash) throw httpError(404, 'That file is not available.');

	// One indexed check that this link's version names this file — a live line photo or a customer-visible
	// attachment — instead of building the whole document once per photo. Trashed files never come back.
	const { data: file, error } = await getQuoteAccessResolverClient()
		.rpc('resolve_quote_access_file', {
			supplied_token_hash: tokenHash,
			target_file_id: event.params.attachmentId
		})
		.maybeSingle();
	if (error || !file || !file.object_key) throw httpError(404, 'That file is not available.');

	const wantsThumbnail = event.url.searchParams.get('size') === 'thumb';
	const objectKey =
		wantsThumbnail && file.thumbnail_object_key ? file.thumbnail_object_key : file.object_key;

	// A photo belongs on the page; anything else is handed over as a file to keep. Serving an arbitrary
	// upload inline from our own origin is how a file turns into a way to run code on our domain.
	const isImage = file.mime_type.startsWith('image/');
	const safeName = file.display_name.replace(/["\\\r\n]/g, '');

	try {
		const object = await getObjectStream(objectKey);
		return new Response(object.body, {
			headers: {
				'content-type': object.contentType ?? file.mime_type,
				...(object.contentLength ? { 'content-length': String(object.contentLength) } : {}),
				'content-disposition': isImage ? 'inline' : `attachment; filename="${safeName}"`,
				'x-content-type-options': 'nosniff',
				'referrer-policy': 'no-referrer',
				// Private, because the link in the URL is the only thing standing between this and a
				// customer's document. No shared cache may keep a copy of it.
				'cache-control': 'private, max-age=3600'
			}
		});
	} catch {
		throw httpError(404, 'That file is not available.');
	}
};
