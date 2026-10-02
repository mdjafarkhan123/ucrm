import { json } from '@sveltejs/kit';
import { validationError } from '$lib/server/api/errors';
import {
	THUMBNAIL_MIME_TYPE,
	buildSupportAttachmentObjectKey,
	buildThumbnailObjectKey,
	createPresignedDownloadUrl,
	createPresignedUploadUrl,
	getObjectStream,
	headObject
} from '$lib/server/storage/r2';
import {
	SUPPORT_ATTACHMENT_TOTAL_BYTES,
	isSupportPhoto,
	type SupportAttachmentUpload,
	type SupportUploadTicket
} from '$lib/support/api';

// Files in a Chat with Uplift (D4b). The customer inbox's paperclip pattern: the browser uploads each file
// straight to storage as it is picked, then the message names the uploads it carries. Both sides use this
// module; the routes decide who is asking and which organization the chat belongs to.

const STORAGE_UNAVAILABLE = 'File storage is not available right now. Try again in a moment.';

/** A file that cannot go with the message, in words the sender can act on. */
export class SupportAttachmentError extends Error {}

// A small copy is a few tens of kilobytes. Anything larger is not one the browser made.
const THUMBNAIL_MAX_BYTES = 1024 * 1024;

export async function createSupportUploadTicket(
	organizationId: string,
	file: { file_name: string; mime_type: string }
): Promise<SupportUploadTicket> {
	const objectKey = buildSupportAttachmentObjectKey(organizationId, file.file_name);
	const photo = isSupportPhoto(file.mime_type);
	const [uploadUrl, thumbnailUploadUrl] = await Promise.all([
		createPresignedUploadUrl(objectKey, file.mime_type),
		photo ? createPresignedUploadUrl(buildThumbnailObjectKey(objectKey), THUMBNAIL_MIME_TYPE) : null
	]);
	return { upload_url: uploadUrl, object_key: objectKey, thumbnail_upload_url: thumbnailUploadUrl };
}

/** The upload-link response both sides give, or a plain refusal when storage is not reachable. */
export async function supportUploadTicketResponse(
	organizationId: string,
	file: { file_name: string; mime_type: string }
): Promise<Response> {
	try {
		return json(await createSupportUploadTicket(organizationId, file), {
			headers: { 'cache-control': 'no-store' }
		});
	} catch {
		return json({ error: STORAGE_UNAVAILABLE }, { status: 503 });
	}
}

export type ResolvedSupportAttachment = {
	object_key: string;
	file_name: string;
	mime_type: string;
	byte_size: number;
	has_thumbnail: boolean;
};

// Measures each upload in storage instead of trusting the browser's word for it, and checks the prefix and
// the 20 MB total up front so a bad file fails with a sentence the sender can act on.
// private.check_support_attachments enforces the same rules again inside the database.
export async function resolveSupportAttachments(
	organizationId: string,
	attachments: SupportAttachmentUpload[]
): Promise<ResolvedSupportAttachment[]> {
	if (attachments.length === 0) return [];

	const prefix = `${organizationId}/support-attachments/`;
	if (attachments.some((attachment) => !attachment.object_key.startsWith(prefix))) {
		throw new SupportAttachmentError('That file does not belong to this conversation.');
	}

	// At most 5 files (the schema's cap) and their small copies: a bounded, independent fan-out.
	const resolved = await Promise.all(
		attachments.map(async (attachment) => {
			let head;
			try {
				head = await headObject(attachment.object_key);
			} catch {
				throw new SupportAttachmentError('That upload did not finish. Add the file again.');
			}
			const byteSize = head.contentLength ?? 0;
			if (byteSize <= 0) {
				throw new SupportAttachmentError('That upload did not finish. Add the file again.');
			}

			const mimeType = head.contentType ?? attachment.mime_type;
			let hasThumbnail = false;
			if (attachment.has_thumbnail && isSupportPhoto(mimeType)) {
				// A missing small copy is not an error: the chat shows the photo itself instead.
				const thumbnail = await headObject(buildThumbnailObjectKey(attachment.object_key)).catch(
					() => null
				);
				const thumbnailBytes = thumbnail?.contentLength ?? 0;
				hasThumbnail = thumbnailBytes > 0 && thumbnailBytes <= THUMBNAIL_MAX_BYTES;
			}

			return {
				object_key: attachment.object_key,
				file_name: attachment.file_name,
				mime_type: mimeType,
				byte_size: byteSize,
				has_thumbnail: hasThumbnail
			};
		})
	);

	const totalBytes = resolved.reduce((sum, attachment) => sum + attachment.byte_size, 0);
	if (totalBytes > SUPPORT_ATTACHMENT_TOTAL_BYTES) {
		throw new SupportAttachmentError('Attachments must total 20 MB or less.');
	}
	return resolved;
}

/** A member's files, measured and ready to store — or the refusal to send back. */
export async function readMemberAttachments(
	organizationId: string,
	attachments: SupportAttachmentUpload[]
): Promise<{ attachments: ResolvedSupportAttachment[] } | { response: Response }> {
	try {
		return { attachments: await resolveSupportAttachments(organizationId, attachments) };
	} catch (error) {
		if (error instanceof SupportAttachmentError)
			return { response: validationError({ attachments: error.message }) };
		throw error;
	}
}

export type StoredSupportAttachment = {
	object_key: string;
	file_name: string;
	mime_type: string;
	has_thumbnail: boolean;
};

// Hands over a file the caller has already been allowed to see.
//
// `?download=1` sends any file to the person's downloads through a short-lived storage link. Otherwise the
// file is shown on the page, and only a photo may be: it streams through here so the `<img>` keeps a plain,
// permanent address (a storage link dies in minutes), with the picture type we stored rather than whatever
// the bytes claim to be. `?size=thumb` asks for the small copy the browser made at upload.
export async function supportAttachmentResponse(
	attachment: StoredSupportAttachment,
	url: URL
): Promise<Response> {
	try {
		if (url.searchParams.has('download')) {
			const downloadUrl = await createPresignedDownloadUrl(
				attachment.object_key,
				attachment.file_name
			);
			return new Response(null, {
				status: 302,
				headers: { location: downloadUrl, 'cache-control': 'no-store' }
			});
		}

		if (!isSupportPhoto(attachment.mime_type))
			return json({ error: 'That file cannot be shown on the page.' }, { status: 415 });

		const wantsThumbnail = url.searchParams.get('size') === 'thumb' && attachment.has_thumbnail;
		const object = await getObjectStream(
			wantsThumbnail ? buildThumbnailObjectKey(attachment.object_key) : attachment.object_key
		);
		return new Response(object.body, {
			headers: {
				'content-type': wantsThumbnail ? THUMBNAIL_MIME_TYPE : attachment.mime_type.toLowerCase(),
				'x-content-type-options': 'nosniff',
				...(object.contentLength ? { 'content-length': String(object.contentLength) } : {}),
				// A key carries a fresh id, so it never points at different bytes later. Private, because the
				// caller's permission check is all that stands between this and another team's files.
				'cache-control': 'private, max-age=86400, immutable'
			}
		});
	} catch {
		return json({ error: STORAGE_UNAVAILABLE }, { status: 503 });
	}
}
