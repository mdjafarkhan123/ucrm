import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { packageRetireSchema } from '$lib/server/validation/package.schema';

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}
	const parsed = packageRetireSchema.safeParse(body);
	if (!parsed.success) return json({ error: 'Please choose a valid package.' }, { status: 422 });
	try {
		const { data, error } = await getOwnerSupabaseClient().rpc('manage_platform_package_version', {
			operation: 'retire',
			target_package_key: parsed.data.package_key,
			actor_email: session.email
		});
		if (error) {
			console.error('Owner package retirement was rejected.', error);
			return json({ error: error.message }, { status: 409 });
		}
		return json({ package_id: data, retired: true });
	} catch (error) {
		console.error('Could not retire owner package.', error);
		return json({ error: 'The package could not be retired.' }, { status: 500 });
	}
};
