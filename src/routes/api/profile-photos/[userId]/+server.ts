import type { RequestHandler } from './$types';
import { databaseError, notFound, unauthorized } from '$lib/server/api/errors';
import { photoResponse } from '$lib/server/profile/photo-routes';
import { userIdParamSchema } from '$lib/server/validation/profile.schema';

// One person's profile photo, for a plain `<img src>`. The read goes through the viewer's own session, so
// RLS on `profiles` decides who may see it: the person themselves and anyone sharing an organization with
// them. A stranger gets the same "not found" as someone with no photo.
export const GET: RequestHandler = async (event) => {
	const user = await event.locals.getUser();
	if (!user) return unauthorized();

	const userId = userIdParamSchema.safeParse(event.params.userId);
	if (!userId.success) return notFound('No photo.');

	const { data, error } = await event.locals.supabase
		.from('profiles')
		.select('avatar_object_key')
		.eq('id', userId.data)
		.maybeSingle();
	if (error) return databaseError();
	if (!data?.avatar_object_key) return notFound('No photo.');

	return photoResponse(event.request, data.avatar_object_key);
};
