import { json } from '@sveltejs/kit';
import type { RequestEvent } from '@sveltejs/kit';
import { getOrganizationContext, type OrganizationContext } from '$lib/server/auth/organization';
import {
	permissionIsEnabled,
	resolveOrganizationAccess,
	type EffectiveOrganizationAccess
} from '$lib/server/access/effective';

export type PermissionCheck =
	{ auth: OrganizationContext; access: EffectiveOrganizationAccess } | { response: Response };

// Resolving access is the expensive part of a gated request, so the resolved answer comes back with the
// check. A route that needs a second permission — money on the Pipeline board, say — asks this instead
// of resolving all over again.
export function hasPermission(access: EffectiveOrganizationAccess, permissionKey: string) {
	return (
		permissionIsEnabled(permissionKey, access.features) &&
		access.permissions[permissionKey] === true
	);
}

// Row level security is the boundary that actually stops the read or write. This check runs first so a
// member without the permission gets a clear answer instead of an empty list or a database error.
//
// Two different "no" answers, kept apart on purpose: the organization's plan does not include the
// feature, or this member is not allowed to use it. The page says something honest either way, and
// neither answer leaks a count or a record.
export async function requireOrganizationPermission(
	event: RequestEvent,
	permissionKey: string
): Promise<PermissionCheck> {
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

		// The permission map already folds the package entitlement in, so this is asked first to tell the
		// two refusals apart rather than to add a second gate.
		if (!permissionIsEnabled(permissionKey, access.features)) {
			return {
				response: json(
					{ error: 'This is not part of your current plan.', reason: 'feature_unavailable' },
					{ status: 403 }
				)
			};
		}

		if (access.permissions[permissionKey] !== true) {
			return {
				response: json(
					{ error: 'You do not have access to do that.', reason: 'permission_denied' },
					{ status: 403 }
				)
			};
		}

		return { auth, access };
	} catch (error) {
		console.error('Could not resolve organization access.', error);
		return { response: json({ error: 'Access could not be verified.' }, { status: 500 }) };
	}
}
