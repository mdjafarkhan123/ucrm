import type { LayoutServerLoad } from './$types';
import { requireOwner } from '$lib/server/auth/owner';
import { ownPlatformPhotoUrl, photoSubject } from '$lib/server/jafar/profile-photo';

export const load: LayoutServerLoad = async (event) => {
	const owner = await requireOwner(event);
	// The top bar's own photo. Without it the panel still opens, showing initials instead.
	let photoUrl: string | null = null;
	try {
		photoUrl = await ownPlatformPhotoUrl(owner);
	} catch (error) {
		console.error('Could not load the signed-in person’s photo.', error);
	}
	return { owner, photo: { id: photoSubject(owner), url: photoUrl } };
};
