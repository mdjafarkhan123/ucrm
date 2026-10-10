import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { OrganizationAccessNotFoundError } from '$lib/server/access/effective';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import { loadAccessComparison } from '$lib/server/experience/access-comparison';

// Multi-industry foundation B5: today's access beside the experience-aware access for this Organization's
// real Package and members. Read-only -- it never changes the Organization's active access path.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	try {
		return json(await loadAccessComparison(getOwnerSupabaseClient(), parsedId.data), {
			headers: { 'cache-control': 'no-store' }
		});
	} catch (error) {
		if (error instanceof OrganizationAccessNotFoundError)
			return json({ error: 'Organization was not found.' }, { status: 404 });
		console.error('Could not compare the organization access.', error);
		return json({ error: 'The access comparison could not be loaded.' }, { status: 500 });
	}
};
