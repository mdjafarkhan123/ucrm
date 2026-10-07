import { json } from '@sveltejs/kit';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { deleteObject, getObjectStream, putObject } from '$lib/server/storage/r2';
import { processProfilePhoto } from '$lib/server/profile/photo';
import {
	PROFILE_PHOTO_MAX_BYTES,
	profilePhotoUploadSchema
} from '$lib/server/validation/profile.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// The steps every profile photo route shares, whoever is signed in: a contractor (`profiles`) or a Jafar
// Panel person (`platform_team_members`, or the owner's settings row). Each route makes its own permission
// check and says where the row lives.

// Room for the multipart envelope around the largest photo allowed.
const MAX_REQUEST_BYTES = PROFILE_PHOTO_MAX_BYTES + 64 * 1024;

/** Stores the photo's bytes under `objectKey(photoId)`, or answers why it cannot. */
export async function storeUploadedPhoto(
	request: Request,
	objectKey: (photoId: string) => string
): Promise<{ response: Response } | { photoId: string; objectKey: string }> {
	const declaredLength = Number(request.headers.get('content-length') ?? 0);
	if (declaredLength > MAX_REQUEST_BYTES) {
		return { response: validationError({ photo: 'That photo is too large.' }, 413) };
	}

	let form: FormData;
	try {
		form = await request.formData();
	} catch {
		return { response: validationError({ photo: 'Choose a photo to upload.' }) };
	}
	const parsed = profilePhotoUploadSchema.safeParse({ photo: form.get('photo') });
	if (!parsed.success) return { response: validationError(zodFieldErrors(parsed.error)) };

	const photo = await processProfilePhoto(new Uint8Array(await parsed.data.photo.arrayBuffer()));
	if (!photo) {
		return { response: validationError({ photo: 'That file could not be read as a photo.' }) };
	}

	const photoId = crypto.randomUUID();
	const key = objectKey(photoId);
	try {
		await putObject(key, photo, 'image/webp');
	} catch {
		return {
			response: json(
				{ error: 'File storage is not configured yet. Ask an admin to set up Cloudflare R2.' },
				{ status: 503, headers: NO_STORE_HEADERS }
			)
		};
	}
	return { photoId, objectKey: key };
}

// Old bytes are removed after the row points elsewhere, so a failed delete costs storage, never a photo.
export async function removeReplacedPhoto(objectKey: string | null) {
	if (!objectKey) return;
	try {
		await deleteObject(objectKey);
	} catch (error) {
		console.warn('Could not delete a replaced profile photo.', { objectKey, error });
	}
}

/** Streams a stored photo after the route has checked the viewer may see it. */
export async function photoResponse(request: Request, objectKey: string): Promise<Response> {
	// Each upload gets a fresh key, and the `?v=` the page asks with changes with it, so the bytes behind
	// one URL never change and the browser may keep them. Private: a permission check stands in front.
	const etag = `"${objectKey}"`;
	const cacheHeaders = { etag, 'cache-control': 'private, max-age=31536000, immutable' };
	if (request.headers.get('if-none-match') === etag) {
		return new Response(null, { status: 304, headers: cacheHeaders });
	}

	try {
		const object = await getObjectStream(objectKey);
		return new Response(object.body, {
			headers: {
				// Only ever written by the upload routes, which re-encode everything to WEBP.
				'content-type': 'image/webp',
				...(object.contentLength ? { 'content-length': String(object.contentLength) } : {}),
				'x-content-type-options': 'nosniff',
				...cacheHeaders
			}
		});
	} catch {
		return json({ error: 'The photo could not be loaded.' }, { status: 503 });
	}
}
