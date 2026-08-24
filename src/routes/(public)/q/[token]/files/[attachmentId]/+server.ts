import { error as httpError } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	getQuoteAccessResolverClient,
	quoteAccessTokenHash
} from '$lib/server/quotes/access-links';
import type { CustomerQuoteDocument } from '$lib/quotes/customer-document';
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

	const supabase = getQuoteAccessResolverClient();
	const { data, error } = await supabase.rpc('resolve_quote_access_link', {
		supplied_token_hash: tokenHash
	});
	if (error || !data) throw httpError(404, 'That file is not available.');

	const document = data as unknown as CustomerQuoteDocument;
	const allowed = new Set<string>([
		...document.attachments.map((attachment) => attachment.id),
		...document.lines
			.map((line) => line.image_attachment_id)
			.filter((id): id is string => typeof id === 'string')
	]);
	if (!allowed.has(event.params.attachmentId)) throw httpError(404, 'That file is not available.');

	const { data: file } = await supabase
		.from('attachments')
		.select('object_key, thumbnail_object_key, mime_type, file_name')
		.eq('id', event.params.attachmentId)
		.maybeSingle();
	if (!file) throw httpError(404, 'That file is not available.');

	const wantsThumbnail = event.url.searchParams.get('size') === 'thumb';
	const objectKey =
		wantsThumbnail && file.thumbnail_object_key ? file.thumbnail_object_key : file.object_key;

	// A photo belongs on the page; anything else is handed over as a file to keep. Serving an arbitrary
	// upload inline from our own origin is how a file turns into a way to run code on our domain.
	const isImage = file.mime_type.startsWith('image/');
	const safeName = file.file_name.replace(/["\\\r\n]/g, '');

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
