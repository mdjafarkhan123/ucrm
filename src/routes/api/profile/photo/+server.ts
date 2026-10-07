import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, unauthorized } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { profilePhotoObjectKey, profilePhotoUrl } from '$lib/server/profile/photo';
import { removeReplacedPhoto, storeUploadedPhoto } from '$lib/server/profile/photo-routes';

const PHOTO_LIMIT = { windowSeconds: 60, maxAttempts: 10 };

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

export const POST: RequestHandler = async (event) => {
	const signedIn = await signedInUser(event);
	if ('response' in signedIn) return signedIn.response;
	const { user } = signedIn;

	const stored = await storeUploadedPhoto(event.request, (photoId) =>
		profilePhotoObjectKey(user.id, photoId)
	);
	if ('response' in stored) return stored.response;

	const { data: previousKey, error } = await getOwnerSupabaseClient().rpc('set_profile_photo', {
		target_user_id: user.id,
		new_photo_id: stored.photoId
	});
	if (error) {
		console.error('Could not save a profile photo.', error);
		await removeReplacedPhoto(stored.objectKey);
		return databaseError();
	}
	await removeReplacedPhoto(previousKey);

	return json(
		{ avatar_url: profilePhotoUrl(user.id, stored.photoId) },
		{ headers: NO_STORE_HEADERS }
	);
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
