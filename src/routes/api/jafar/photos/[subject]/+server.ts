import type { RequestHandler } from './$types';
import { databaseError, notFound } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { platformPhotoObjectKeyFor } from '$lib/server/jafar/profile-photo';
import { photoResponse } from '$lib/server/profile/photo-routes';
import { platformPhotoSubjectSchema } from '$lib/server/validation/profile.schema';

// Jafar's or a teammate's photo, for a plain `<img src>`. Anyone signed in to the Jafar Panel may see the
// people they work with; nobody else, contractors included, reaches this route past the panel's gate.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const subject = platformPhotoSubjectSchema.safeParse(event.params.subject);
	if (!subject.success) return notFound('No photo.');

	let objectKey: string | null;
	try {
		objectKey = await platformPhotoObjectKeyFor(subject.data);
	} catch {
		return databaseError();
	}
	if (!objectKey) return notFound('No photo.');

	return photoResponse(event.request, objectKey);
};
