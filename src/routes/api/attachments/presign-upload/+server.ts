import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	requireLinkedEntityAccess,
	linkedEntityBelongsToOrganization
} from '$lib/server/access/collaboration';
import { validationError } from '$lib/server/api/errors';
import { attachmentPresignSchema } from '$lib/server/validation/collaboration.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	buildAttachmentObjectKey,
	buildThumbnailObjectKey,
	createPresignedUploadUrl,
	THUMBNAIL_MIME_TYPE
} from '$lib/server/storage/r2';

export const POST: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = attachmentPresignSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const access = await requireLinkedEntityAccess(event, parsed.data.entity_type, 'manage');
	if ('response' in access) return access.response;

	const organizationId = access.auth.organization.id;
	const belongs = await linkedEntityBelongsToOrganization(
		event.locals.supabase,
		organizationId,
		parsed.data.entity_type,
		parsed.data.entity_id
	);
	if (!belongs) return validationError({ entity_id: 'That record was not found.' });

	const objectKey = buildAttachmentObjectKey(
		organizationId,
		parsed.data.entity_type,
		parsed.data.entity_id,
		parsed.data.file_name
	);

	// A photo also gets a slot for its small preview. The browser decides whether to fill it — it cannot
	// decode every format — so the caller may upload nothing here and leave the thumbnail unset.
	const isImage = parsed.data.mime_type.startsWith('image/');
	const thumbnailObjectKey = isImage ? buildThumbnailObjectKey(objectKey) : null;

	let uploadUrl: string;
	let thumbnailUploadUrl: string | null = null;
	try {
		uploadUrl = await createPresignedUploadUrl(objectKey, parsed.data.mime_type);
		if (thumbnailObjectKey)
			thumbnailUploadUrl = await createPresignedUploadUrl(thumbnailObjectKey, THUMBNAIL_MIME_TYPE);
	} catch {
		return json(
			{ error: 'File storage is not configured yet. Ask an admin to set up Cloudflare R2.' },
			{ status: 503 }
		);
	}

	return json({
		upload_url: uploadUrl,
		object_key: objectKey,
		thumbnail_upload_url: thumbnailUploadUrl,
		thumbnail_object_key: thumbnailObjectKey
	});
};
