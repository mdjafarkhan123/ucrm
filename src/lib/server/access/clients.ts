import { json } from '@sveltejs/kit';
import type { RequestEvent } from '@sveltejs/kit';
import { getOrganizationContext, type OrganizationContext } from '$lib/server/auth/organization';
import { resolveOrganizationAccess } from '$lib/server/access/effective';

// Row level security is the boundary that actually stops the write. This check runs first so a member
// without the permission gets a clear 403 instead of a database error.
export async function requireClientPermission(
	event: RequestEvent,
	permissionKey: string
): Promise<{ auth: OrganizationContext } | { response: Response }> {
	const auth = await getOrganizationContext(event);
	if (!auth) {
		return {
			response: json(
				{ error: 'Authentication or organization membership required.' },
				{ status: 401 }
			)
		};
	}

	try {
		const access = await resolveOrganizationAccess(
			event.locals.supabase,
			auth.organization.id,
			auth.user.id
		);
		if (access.permissions[permissionKey] !== true) {
			return { response: json({ error: 'You do not have access to do that.' }, { status: 403 }) };
		}
		return { auth };
	} catch (error) {
		console.error('Could not resolve client access.', error);
		return { response: json({ error: 'Access could not be verified.' }, { status: 500 }) };
	}
}
