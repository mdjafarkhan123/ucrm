import { json, type RequestEvent } from '@sveltejs/kit';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';

// The package system is being replaced (package-builder, ADR 0003). Until each replacement arrives, the
// old package, exception, free-access, payment, and activation writes answer this instead of writing to
// tables nothing reads any more. Each later part deletes the routes it replaces.
export async function packageSystemRebuilding(event: RequestEvent) {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	return json(
		{
			error:
				'This is switched off while the package system is rebuilt. It comes back with the new package tools.',
			reason: 'package_system_rebuilding'
		},
		{ status: 410 }
	);
}
