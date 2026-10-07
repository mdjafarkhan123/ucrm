import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession, type OwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	photoSubject,
	platformPhotoObjectKey,
	platformPhotoUrl,
	setPlatformPhoto
} from '$lib/server/jafar/profile-photo';
import { removeReplacedPhoto, storeUploadedPhoto } from '$lib/server/profile/photo-routes';

const PHOTO_LIMIT = { windowSeconds: 60, maxAttempts: 10 };

// The signed-in Jafar Panel person's own photo — Jafar's or a teammate's. Whose it is comes from the
// session alone; there is no id to send, so nobody changes someone else's.
async function signedInPerson(
	event: Parameters<RequestHandler>[0]
): Promise<{ response: Response } | { session: OwnerSession }> {
	const session = await getOwnerSession(event);
	if (!session) return { response: ownerUnauthorized() };

	let limit;
	try {
		limit = await checkRateLimit(getOwnerSupabaseClient(), {
			bucketKey: `jafar-photo:${photoSubject(session)}`,
			...PHOTO_LIMIT
		});
	} catch {
		return { response: databaseError() };
	}
	if (!limit.allowed) return { response: rateLimitedResponse(limit.retryAfterSeconds) };
	return { session };
}

export const POST: RequestHandler = async (event) => {
	const signedIn = await signedInPerson(event);
	if ('response' in signedIn) return signedIn.response;
	const subject = photoSubject(signedIn.session);

	const stored = await storeUploadedPhoto(event.request, (photoId) =>
		platformPhotoObjectKey(subject, photoId)
	);
	if ('response' in stored) return stored.response;

	let previousKey: string | null;
	try {
		previousKey = await setPlatformPhoto(signedIn.session, stored.photoId);
	} catch (error) {
		console.error('Could not save a Jafar Panel profile photo.', error);
		await removeReplacedPhoto(stored.objectKey);
		return databaseError();
	}
	await removeReplacedPhoto(previousKey);

	return json(
		{ avatar_url: platformPhotoUrl(subject, stored.photoId) },
		{ headers: NO_STORE_HEADERS }
	);
};

export const DELETE: RequestHandler = async (event) => {
	const signedIn = await signedInPerson(event);
	if ('response' in signedIn) return signedIn.response;

	let previousKey: string | null;
	try {
		previousKey = await setPlatformPhoto(signedIn.session, null);
	} catch (error) {
		console.error('Could not remove a Jafar Panel profile photo.', error);
		return databaseError();
	}
	await removeReplacedPhoto(previousKey);

	return json({ avatar_url: null }, { headers: NO_STORE_HEADERS });
};
