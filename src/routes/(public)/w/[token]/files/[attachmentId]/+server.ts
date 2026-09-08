import { error as httpError } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	getJobReportAccessResolverClient,
	jobReportAccessTokenHash
} from '$lib/server/jobs/report-access-links';
import type { CustomerJobReportDocument } from '$lib/jobs/report-types';
import { getObjectStream } from '$lib/server/storage/r2';

// Photos on the customer's copy of a work report. The token buys one document, so it buys exactly the photos
// that document names -- everything else, including the same organization's other files, is a plain 404
// here. There is no shareable storage URL anywhere in this: the bytes are streamed through this request,
// which dies with the link.
export const GET: RequestHandler = async (event) => {
	const tokenHash = jobReportAccessTokenHash(event.params.token);
	if (!tokenHash) throw httpError(404, 'That file is not available.');

	const supabase = getJobReportAccessResolverClient();
	const { data, error } = await supabase.rpc('resolve_job_report_access_link', {
		supplied_token_hash: tokenHash
	});
	if (error || !data) throw httpError(404, 'That file is not available.');

	const document = data as unknown as CustomerJobReportDocument;
	const allowed = new Set(document.photos.map((photo) => photo.attachment_id));
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

	const safeName = file.file_name.replace(/["\\\r\n]/g, '');

	try {
		const object = await getObjectStream(objectKey);
		return new Response(object.body, {
			headers: {
				'content-type': object.contentType ?? file.mime_type,
				...(object.contentLength ? { 'content-length': String(object.contentLength) } : {}),
				'content-disposition': `inline; filename="${safeName}"`,
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
