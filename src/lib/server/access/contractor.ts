import { json } from '@sveltejs/kit';
import type { RequestEvent } from '@sveltejs/kit';
import { getOrganizationContext } from '$lib/server/auth/organization';
import {
	permissionIsEnabled,
	resolveOrganizationAccess,
	type EffectiveOrganizationAccess
} from '$lib/server/access/effective';

export const CONTRACTOR_ROLES = ['owner', 'admin', 'office', 'sales', 'field', 'finance'] as const;
export type ContractorRole = (typeof CONTRACTOR_ROLES)[number];

export type ContractorTeamAdminContext = {
	auth: NonNullable<Awaited<ReturnType<typeof getOrganizationContext>>>;
	access: EffectiveOrganizationAccess;
};

export function isContractorRole(value: string): value is ContractorRole {
	return (CONTRACTOR_ROLES as readonly string[]).includes(value);
}

export async function requireContractorTeamAdmin(
	event: RequestEvent
): Promise<{ context: ContractorTeamAdminContext } | { response: Response }> {
	const auth = await getOrganizationContext(event);
	if (!auth) {
		return {
			response: json(
				{ error: 'Authentication or organization membership required.' },
				{ status: 401 }
			)
		};
	}

	if (auth.organization.role !== 'owner' && auth.organization.role !== 'admin') {
		return {
			response: json({ error: 'Organization administrator access required.' }, { status: 403 })
		};
	}

	try {
		const access = await resolveOrganizationAccess(
			event.locals.supabase,
			auth.organization.id,
			auth.user.id
		);
		if (
			access.organization.lifecycle_status !== 'active' ||
			!access.features['core.team'] ||
			access.permissions['team.manage'] !== true
		) {
			return {
				response: json(
					{ error: 'Team management is not enabled for this organization.' },
					{ status: 403 }
				)
			};
		}
		return { context: { auth, access } };
	} catch (error) {
		console.error('Could not resolve contractor team access.', error);
		return {
			response: json({ error: 'Team access could not be verified.' }, { status: 500 })
		};
	}
}

export function resolveMemberPermissionMap(
	rolePermissionKeys: Iterable<string>,
	overrides: Iterable<{ permission_key: string; override_state: string }>,
	features: Record<string, boolean>
) {
	const permissions = new Map<string, boolean>();
	for (const permissionKey of rolePermissionKeys) permissions.set(permissionKey, true);
	for (const override of overrides) {
		permissions.set(override.permission_key, override.override_state === 'grant');
	}

	return Object.fromEntries(
		[...permissions.entries()].map(([permissionKey, enabled]) => [
			permissionKey,
			enabled && permissionIsEnabled(permissionKey, features)
		])
	);
}
