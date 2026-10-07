import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { databaseError, notFound, unauthorized } from '$lib/server/api/errors';
import { getObjectStream } from '$lib/server/storage/r2';
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

	// Each upload gets a fresh key, and the `?v=` the page asks with changes with it, so the bytes behind
	// one URL never change and the browser may keep them. Private: a permission check stands in front.
	const etag = `"${data.avatar_object_key}"`;
	const cacheHeaders = { etag, 'cache-control': 'private, max-age=31536000, immutable' };
	if (event.request.headers.get('if-none-match') === etag) {
		return new Response(null, { status: 304, headers: cacheHeaders });
	}

	try {
		const object = await getObjectStream(data.avatar_object_key);
		return new Response(object.body, {
			headers: {
				// Only ever written by the upload route, which re-encodes everything to WEBP.
				'content-type': 'image/webp',
				...(object.contentLength ? { 'content-length': String(object.contentLength) } : {}),
				'x-content-type-options': 'nosniff',
				...cacheHeaders
			}
		});
	} catch {
		return json({ error: 'The photo could not be loaded.' }, { status: 503 });
	}
};
