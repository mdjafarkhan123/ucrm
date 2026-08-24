import { error as httpError } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { getObjectStream } from '$lib/server/storage/r2';

// The drawn signature itself. There is no shareable URL for it anywhere: the bytes are streamed through
// this request, which needs a session and the permission to see the quote. The row is read through the
// member's own client, so row level security decides whether it exists at all — and the quote in the URL
// has to be the quote the signature belongs to, so one quote's link can never fetch another's.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.view');
	if ('response' in check) return check.response;

	const { data: signature } = await event.locals.supabase
		.from('quote_signatures')
		.select('image_object_key')
		.eq('id', event.params.signatureId)
		.eq('quote_id', event.params.id)
		.maybeSingle();

	if (!signature?.image_object_key) throw httpError(404, 'That signature is not available.');

	try {
		const object = await getObjectStream(signature.image_object_key);
		return new Response(object.body, {
			headers: {
				'content-type': object.contentType ?? 'image/png',
				...(object.contentLength ? { 'content-length': String(object.contentLength) } : {}),
				'content-disposition': 'inline',
				'x-content-type-options': 'nosniff',
				'referrer-policy': 'no-referrer',
				// A signature is immutable once written, so it caches hard — privately, because it is one
				// person's name in their own hand and no shared cache may keep a copy.
				'cache-control': 'private, max-age=3600'
			}
		});
	} catch {
		throw httpError(404, 'That signature is not available.');
	}
};
