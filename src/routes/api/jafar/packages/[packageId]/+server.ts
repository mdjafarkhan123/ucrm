import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { packageIdSchema } from '$lib/server/validation/package-builder.schema';

// Package builder P6: one package for the builder, with its draft, published terms, and the capability
// and allowance reference data the form is built from.

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const parsedId = packageIdSchema.safeParse(event.params.packageId);
	if (!parsedId.success)
		return json({ error: 'The package identifier is invalid.' }, { status: 422 });

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_package_builder', {
		target_package_id: parsedId.data
	});
	if (error) {
		console.error('Could not load the package.', error);
		return json({ error: 'The package could not be loaded.' }, { status: 500 });
	}
	if (!data) return json({ error: 'Package was not found.' }, { status: 404 });
	return json({ builder: data }, { headers: { 'cache-control': 'no-store' } });
};
