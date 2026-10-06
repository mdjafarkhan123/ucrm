import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { ownerPackageCommandError } from '$lib/server/packages/owner-package-errors';
import {
	packageCatalogActionSchema,
	packageIdSchema,
	type PackageCatalogAction
} from '$lib/server/validation/package-builder.schema';

// Package builder P6: one package for the builder, with its draft, published terms, and the capability
// and allowance reference data the form is built from. P7 adds the catalog actions (visibility, order,
// archive, restore, website confirmation), which change the package and never an edition's terms.

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

function runCatalogAction(packageId: string, command: PackageCatalogAction, actor: string) {
	const client = getOwnerSupabaseClient();
	switch (command.action) {
		case 'set_visibility':
			return client.rpc('set_package_visibility', {
				target_package_id: packageId,
				new_visibility: command.visibility,
				actor_owner_email: actor
			});
		case 'move':
			return client.rpc('move_package', {
				target_package_id: packageId,
				direction: command.direction,
				actor_owner_email: actor
			});
		case 'archive':
		case 'restore':
			return client.rpc('set_package_archived', {
				target_package_id: packageId,
				archived: command.action === 'archive',
				actor_owner_email: actor
			});
		case 'confirm_website':
			return client.rpc('confirm_package_website_update', {
				target_package_id: packageId,
				seen_pending_since: command.pending_since,
				actor_owner_email: actor
			});
	}
}

export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const parsedId = packageIdSchema.safeParse(event.params.packageId);
	if (!parsedId.success)
		return json({ error: 'The package identifier is invalid.' }, { status: 422 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}
	const parsed = packageCatalogActionSchema.safeParse(body);
	if (!parsed.success) return json({ error: 'The package change is invalid.' }, { status: 422 });

	const { data, error } = await runCatalogAction(parsedId.data, parsed.data, session.email);
	if (error) {
		const refused = ownerPackageCommandError(error);
		if (refused) return refused;
		console.error(`Could not ${parsed.data.action} the package.`, error);
		return json({ error: 'The package could not be changed.' }, { status: 500 });
	}
	const result = data as { applied?: boolean; confirmed?: boolean; reason?: string };
	if (result.confirmed === false && result.reason === 'stale') {
		return json(
			{
				error:
					'The package changed again since you saw the reminder. Check the latest changes first.',
				reason: 'stale'
			},
			{ status: 409 }
		);
	}
	return json({ applied: result.applied ?? false });
};

// Deleting removes a package nobody ever used, editions and all. The database refuses, with the reason in
// plain words, once a customer, application, offer, template, or public listing depends on it.
export const DELETE: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const parsedId = packageIdSchema.safeParse(event.params.packageId);
	if (!parsedId.success)
		return json({ error: 'The package identifier is invalid.' }, { status: 422 });

	const { error } = await getOwnerSupabaseClient().rpc('delete_package', {
		target_package_id: parsedId.data,
		actor_owner_email: session.email
	});
	if (error) {
		const refused = ownerPackageCommandError(error);
		if (refused) return refused;
		console.error('Could not delete the package.', error);
		return json({ error: 'The package could not be deleted.' }, { status: 500 });
	}
	return json({ deleted: true });
};
