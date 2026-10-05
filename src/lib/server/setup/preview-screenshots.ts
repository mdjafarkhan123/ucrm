import { json } from '@sveltejs/kit';
import { validationError } from '$lib/server/api/errors';
import {
	THUMBNAIL_MIME_TYPE,
	buildSetupPreviewObjectKey,
	buildThumbnailObjectKey,
	createPresignedUploadUrl,
	getObjectStream,
	headObject
} from '$lib/server/storage/r2';
import {
	PREVIEW_SCREENSHOTS_TOTAL_BYTES,
	PREVIEW_SCREENSHOT_BYTES_MAX,
	PREVIEW_SCREENSHOT_TYPES,
	type PreviewScreenshot
} from '$lib/setup/preview';

// Client onboarding E3: screenshots on preview cards and on the client's notes. Chat with Uplift's pattern
// ($lib/server/support/attachments.ts): the browser uploads each photo straight to storage with a small copy,
// then the save names the uploads, and this module measures them in storage rather than trusting the browser.
// Every key sits under the client's own `<org>/setup-previews/` prefix, whoever uploaded it.

const STORAGE_UNAVAILABLE = 'File storage is not available right now. Try again in a moment.';
const THUMBNAIL_MAX_BYTES = 1024 * 1024;

const isPhoto = (mimeType: string) =>
	(PREVIEW_SCREENSHOT_TYPES as readonly string[]).includes(mimeType.toLowerCase());

export const previewScreenshotPrefix = (organizationId: string) =>
	`${organizationId}/setup-previews/`;

/** Somewhere to upload one screenshot and its small copy, or a plain refusal when storage is not reachable. */
export async function previewUploadTicketResponse(
	organizationId: string,
	file: { file_name: string; mime_type: string }
): Promise<Response> {
	try {
		const objectKey = buildSetupPreviewObjectKey(organizationId, file.file_name);
		const [uploadUrl, thumbnailUploadUrl] = await Promise.all([
			createPresignedUploadUrl(objectKey, file.mime_type),
			createPresignedUploadUrl(buildThumbnailObjectKey(objectKey), THUMBNAIL_MIME_TYPE)
		]);
		return json(
			{ upload_url: uploadUrl, object_key: objectKey, thumbnail_upload_url: thumbnailUploadUrl },
			{ headers: { 'cache-control': 'no-store' } }
		);
	} catch {
		return json({ error: STORAGE_UNAVAILABLE }, { status: 503 });
	}
}

type ScreenshotUpload = {
	object_key: string;
	file_name: string;
	mime_type: string;
	has_thumbnail: boolean;
};

/**
 * The screenshots, measured and ready to store — or the refusal to send back. A key already stored needs no new
 * upload, but is measured again all the same: at most 5 small HEAD requests per card.
 */
export async function resolvePreviewScreenshots(
	organizationId: string,
	uploads: ScreenshotUpload[]
): Promise<{ screenshots: PreviewScreenshot[] } | { response: Response }> {
	if (uploads.length === 0) return { screenshots: [] };
	const refuse = (message: string) => ({ response: validationError({ screenshots: message }) });

	if (
		uploads.some((upload) => !upload.object_key.startsWith(previewScreenshotPrefix(organizationId)))
	)
		return refuse('That screenshot does not belong to this preview.');

	let screenshots: PreviewScreenshot[];
	try {
		screenshots = await Promise.all(
			uploads.map(async (upload) => {
				const head = await headObject(upload.object_key);
				const byteSize = head.contentLength ?? 0;
				if (byteSize <= 0) throw new Error('empty');
				const mimeType = (head.contentType ?? upload.mime_type).toLowerCase();
				let hasThumbnail = false;
				if (upload.has_thumbnail) {
					const thumbnail = await headObject(buildThumbnailObjectKey(upload.object_key)).catch(
						() => null
					);
					const bytes = thumbnail?.contentLength ?? 0;
					hasThumbnail = bytes > 0 && bytes <= THUMBNAIL_MAX_BYTES;
				}
				return {
					object_key: upload.object_key,
					file_name: upload.file_name,
					mime_type: isPhoto(mimeType) ? mimeType : upload.mime_type,
					byte_size: byteSize,
					has_thumbnail: hasThumbnail
				};
			})
		);
	} catch {
		return refuse('A screenshot did not finish uploading. Add it again.');
	}

	if (screenshots.some((shot) => shot.byte_size > PREVIEW_SCREENSHOT_BYTES_MAX))
		return refuse('Each screenshot must be 10 MB or smaller.');
	if (screenshots.reduce((sum, shot) => sum + shot.byte_size, 0) > PREVIEW_SCREENSHOTS_TOTAL_BYTES)
		return refuse('Keep the screenshots to 20 MB together.');
	return { screenshots };
}

/**
 * Streams one screenshot the caller may see, through a plain permanent address so a cached page never holds a
 * dead storage link. The caller has checked who is asking; this checks the key is the organization's.
 */
export async function previewScreenshotResponse(
	organizationId: string,
	url: URL
): Promise<Response> {
	const key = url.searchParams.get('key') ?? '';
	if (!key.startsWith(previewScreenshotPrefix(organizationId)) || key.includes('..'))
		return json({ error: 'That screenshot could not be found.' }, { status: 404 });
	const wantsThumbnail = url.searchParams.get('size') === 'thumb';
	try {
		const object = await getObjectStream(wantsThumbnail ? buildThumbnailObjectKey(key) : key);
		const type = wantsThumbnail ? THUMBNAIL_MIME_TYPE : (object.contentType ?? '').toLowerCase();
		if (!isPhoto(type) && type !== THUMBNAIL_MIME_TYPE)
			return json({ error: 'That file cannot be shown on the page.' }, { status: 415 });
		return new Response(object.body, {
			headers: {
				'content-type': type,
				'x-content-type-options': 'nosniff',
				...(object.contentLength ? { 'content-length': String(object.contentLength) } : {}),
				// A key carries a fresh id, so it never points at different bytes later.
				'cache-control': 'private, max-age=86400, immutable'
			}
		});
	} catch {
		return json({ error: 'That screenshot could not be found.' }, { status: 404 });
	}
}
