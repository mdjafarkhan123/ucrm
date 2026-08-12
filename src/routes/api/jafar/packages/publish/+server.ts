import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { packageVersionPublishSchema } from '$lib/server/validation/package.schema';

export const POST: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}
	const parsed = packageVersionPublishSchema.safeParse(body);
	if (!parsed.success)
		return json({ error: 'Please choose a valid draft version.' }, { status: 422 });

	try {
		const { data, error } = await getOwnerSupabaseClient().rpc('manage_platform_package_version', {
			operation: 'publish',
			target_package_key: parsed.data.package_key,
			target_version_id: parsed.data.version_id,
			actor_email: session.email
		});
		if (error) {
			console.error('Owner package publication was rejected.', error);
			return json({ error: 'The package version could not be published.' }, { status: 409 });
		}
		return json({ version_id: data, published: true });
	} catch (error) {
		console.error('Could not publish owner package version.', error);
		return json({ error: 'The package version could not be published.' }, { status: 500 });
	}
};
