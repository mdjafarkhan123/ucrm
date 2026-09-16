import { error as httpError } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	getSmsAttachmentAccessResolverClient,
	smsAttachmentAccessTokenHash
} from '$lib/server/communications/sms-attachment-access-links';
import { getObjectStream } from '$lib/server/storage/r2';

// The customer's door to a picture/file an SMS could not send as real MMS media (Stage 6D-3). Unlike the
// quote/invoice/job-report links, there is exactly one file behind this token -- no intermediate document
// page, the link itself streams the bytes straight through, same as job_report_access_links' own file route.
// Every way of failing looks like a plain 404: unknown token or a broken upload are indistinguishable to a
// stranger walking the URL space.
export const GET: RequestHandler = async (event) => {
	const tokenHash = smsAttachmentAccessTokenHash(event.params.token);
	if (!tokenHash) throw httpError(404, 'That file is not available.');

	const supabase = getSmsAttachmentAccessResolverClient();
	const { data, error } = await supabase.rpc('resolve_communication_sms_attachment_access_link', {
		supplied_token_hash: tokenHash
	});
	if (error || !data) throw httpError(404, 'That file is not available.');

	const file = data as { object_key: string; mime_type: string; file_name: string };
	const safeName = file.file_name.replace(/["\\\r\n]/g, '');

	try {
		const object = await getObjectStream(file.object_key);
		return new Response(object.body, {
			headers: {
				'content-type': object.contentType ?? file.mime_type,
				...(object.contentLength ? { 'content-length': String(object.contentLength) } : {}),
				'content-disposition': `inline; filename="${safeName}"`,
				'x-content-type-options': 'nosniff',
				'referrer-policy': 'no-referrer',
				'x-robots-tag': 'noindex, nofollow, noarchive',
				// Private, because the token in the URL is the only thing standing between this and a
				// customer's file. No shared cache may keep a copy of it.
				'cache-control': 'private, max-age=3600'
			}
		});
	} catch {
		throw httpError(404, 'That file is not available.');
	}
};
