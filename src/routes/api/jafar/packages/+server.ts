import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { ownerPackageCommandError } from '$lib/server/packages/owner-package-errors';
import {
	createPackageSchema,
	packageFieldErrors
} from '$lib/server/validation/package-builder.schema';

// Package builder P6: the Packages page lists every package and creates new ones, blank or copied.

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const { data, error } = await getOwnerSupabaseClient().rpc('owner_package_catalog');
	if (error) {
		console.error('Could not load the package catalog.', error);
		return json({ error: 'Packages could not be loaded.' }, { status: 500 });
	}
	return json({ packages: data ?? [] }, { headers: { 'cache-control': 'no-store' } });
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = createPackageSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the package details.',
				field_errors: packageFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	const { data, error } = await getOwnerSupabaseClient().rpc('create_package_draft', {
		slug: parsed.data.slug,
		name: parsed.data.name,
		actor_owner_email: session.email,
		idempotency_key: parsed.data.idempotency_key,
		copy_from_package_id: parsed.data.copy_from_package_id ?? undefined
	});
	if (error) {
		const refused = ownerPackageCommandError(error);
		if (refused) return refused;
		console.error('Could not create the package.', error);
		return json({ error: 'The package could not be created.' }, { status: 500 });
	}
	return json({ result: data }, { status: 201 });
};
