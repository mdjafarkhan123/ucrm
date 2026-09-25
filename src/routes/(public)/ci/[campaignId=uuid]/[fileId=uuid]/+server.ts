import { error as httpError } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getObjectStream } from '$lib/server/storage/r2';

// A campaign image block's door for the one reader who never has a session: the recipient's own mail client,
// fetching the <img src> straight out of a delivered email. There is no per-recipient token here -- the same
// picture goes out to every recipient of this campaign, so the only thing standing between this and a
// stranger is the pair of uuids in the URL, exactly the trust level any link already going out to a whole
// customer list carries. The actual gate is file_links: this file_id must really be linked to this campaign
// as an image, or it is a plain 404, indistinguishable from an unknown id.
export const GET: RequestHandler = async ({ params }) => {
	const supabase = getOwnerSupabaseClient();

	const { data: link } = await supabase
		.from('file_links')
		.select('file_id')
		.eq('entity_type', 'marketing_campaign')
		.eq('entity_id', params.campaignId)
		.eq('file_id', params.fileId)
		.eq('role', 'campaign_image')
		.maybeSingle();
	if (!link) throw httpError(404, 'That image is not available.');

	const { data: file } = await supabase
		.from('files')
		.select('object_key, mime_type, processing_state, trashed_at')
		.eq('id', params.fileId)
		.maybeSingle();
	if (
		!file ||
		file.processing_state !== 'available' ||
		file.trashed_at !== null ||
		!file.object_key
	) {
		throw httpError(404, 'That image is not available.');
	}

	try {
		const object = await getObjectStream(file.object_key);
		return new Response(object.body, {
			headers: {
				'content-type': object.contentType ?? file.mime_type,
				...(object.contentLength ? { 'content-length': String(object.contentLength) } : {}),
				'content-disposition': 'inline',
				'x-content-type-options': 'nosniff',
				'referrer-policy': 'no-referrer',
				'x-robots-tag': 'noindex, nofollow, noarchive',
				// Public and immutable, unlike every other file route here: this is meant to be fetched by a
				// mail client with no cookies at all, often through a provider's own image proxy (Gmail's
				// among them) that only bothers caching what a shared cache is allowed to keep. The object key
				// itself never changes its bytes, so there is nothing this could serve stale.
				'cache-control': 'public, max-age=86400, immutable'
			}
		});
	} catch {
		throw httpError(404, 'That image is not available.');
	}
};
