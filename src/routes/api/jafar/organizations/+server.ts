import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

function unauthorized() {
	return json({ error: 'Platform owner authentication required.' }, { status: 401 });
}

export const GET: RequestHandler = async (event) => {
	if (!getOwnerSession(event)) return unauthorized();

	try {
		const { data, error } = await getOwnerSupabaseClient()
			.from('organizations')
			.select(
				'id, name, slug, lifecycle_status, created_at, updated_at, organization_members(user_id, role)'
			)
			.order('created_at', { ascending: false });
		if (error) {
			console.error('Could not list organizations.', error);
			return json({ error: 'Organizations could not be loaded.' }, { status: 500 });
		}
		return json({ organizations: data ?? [] });
	} catch (error) {
		console.error('Organization service is unavailable.', error);
		return json({ error: 'Organization provisioning is not configured.' }, { status: 503 });
	}
};
