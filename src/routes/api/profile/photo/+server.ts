import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	NO_STORE_HEADERS,
	databaseError,
	unauthorized,
	validationError
} from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { deleteObject, putObject } from '$lib/server/storage/r2';
import {
	processProfilePhoto,
	profilePhotoObjectKey,
	profilePhotoUrl
} from '$lib/server/profile/photo';
import {
	PROFILE_PHOTO_MAX_BYTES,
	profilePhotoUploadSchema
} from '$lib/server/validation/profile.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const PHOTO_LIMIT = { windowSeconds: 60, maxAttempts: 10 };
// Room for the multipart envelope around the largest photo allowed.
const MAX_REQUEST_BYTES = PROFILE_PHOTO_MAX_BYTES + 64 * 1024;

// The signed-in person's own photo. Nobody sets a photo for someone else: there is no user id to send.
async function signedInUser(
	event: Parameters<RequestHandler>[0]
): Promise<{ response: Response } | { user: { id: string } }> {
	const user = await event.locals.getUser();
	if (!user) return { response: unauthorized() };

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `profile-photo:${user.id}`,
			...PHOTO_LIMIT
		});
	} catch {
		return { response: databaseError() };
	}
	if (!limit.allowed) return { response: rateLimitedResponse(limit.retryAfterSeconds) };
	return { user };
}

// Old bytes are removed after the row points elsewhere, so a failed delete costs storage, never a photo.
async function removeReplacedPhoto(objectKey: string | null) {
	if (!objectKey) return;
	try {
		await deleteObject(objectKey);
	} catch (error) {
		console.warn('Could not delete a replaced profile photo.', { objectKey, error });
	}
}

export const POST: RequestHandler = async (event) => {
	const signedIn = await signedInUser(event);
	if ('response' in signedIn) return signedIn.response;
	const { user } = signedIn;

	const declaredLength = Number(event.request.headers.get('content-length') ?? 0);
	if (declaredLength > MAX_REQUEST_BYTES) {
		return validationError({ photo: 'That photo is too large.' }, 413);
	}

	let form: FormData;
	try {
		form = await event.request.formData();
	} catch {
		return validationError({ photo: 'Choose a photo to upload.' });
	}
	const parsed = profilePhotoUploadSchema.safeParse({ photo: form.get('photo') });
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const photo = await processProfilePhoto(new Uint8Array(await parsed.data.photo.arrayBuffer()));
	if (!photo) return validationError({ photo: 'That file could not be read as a photo.' });

	const photoId = crypto.randomUUID();
	const objectKey = profilePhotoObjectKey(user.id, photoId);
	try {
		await putObject(objectKey, photo, 'image/webp');
	} catch {
		return json(
			{ error: 'File storage is not configured yet. Ask an admin to set up Cloudflare R2.' },
			{ status: 503, headers: NO_STORE_HEADERS }
		);
	}

	const { data: previousKey, error } = await getOwnerSupabaseClient().rpc('set_profile_photo', {
		target_user_id: user.id,
		new_photo_id: photoId
	});
	if (error) {
		console.error('Could not save a profile photo.', error);
		await removeReplacedPhoto(objectKey);
		return databaseError();
	}
	await removeReplacedPhoto(previousKey);

	return json({ avatar_url: profilePhotoUrl(user.id, photoId) }, { headers: NO_STORE_HEADERS });
};

export const DELETE: RequestHandler = async (event) => {
	const signedIn = await signedInUser(event);
	if ('response' in signedIn) return signedIn.response;

	const { data: previousKey, error } = await getOwnerSupabaseClient().rpc('set_profile_photo', {
		target_user_id: signedIn.user.id
	});
	if (error) {
		console.error('Could not remove a profile photo.', error);
		return databaseError();
	}
	await removeReplacedPhoto(previousKey);

	return json({ avatar_url: null }, { headers: NO_STORE_HEADERS });
};
