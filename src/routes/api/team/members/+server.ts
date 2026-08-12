import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	CONTRACTOR_ROLES,
	requireContractorTeamAdmin,
	resolveMemberPermissionMap
} from '$lib/server/access/contractor';

export const GET: RequestHandler = async (event) => {
	const required = await requireContractorTeamAdmin(event);
	if ('response' in required) return required.response;

	const { auth, access } = required.context;
	const [membersResult, permissionsResult, rolePermissionsResult, overridesResult] =
		await Promise.all([
			event.locals.supabase
				.from('organization_members')
				.select('user_id, role, created_at')
				.eq('organization_id', auth.organization.id)
				.order('created_at', { ascending: true }),
			event.locals.supabase.from('permissions').select('key, description').order('key'),
			event.locals.supabase.from('role_permissions').select('role, permission_key'),
			event.locals.supabase
				.from('organization_member_permission_overrides')
				.select('user_id, permission_key, override_state')
				.eq('organization_id', auth.organization.id)
		]);

	if (
		membersResult.error ||
		permissionsResult.error ||
		rolePermissionsResult.error ||
		overridesResult.error
	) {
		console.error('Could not load contractor team access.', {
			members: membersResult.error,
			permissions: permissionsResult.error,
			rolePermissions: rolePermissionsResult.error,
			overrides: overridesResult.error
		});
		return json({ error: 'Team members could not be loaded.' }, { status: 500 });
	}

	const rolePermissions = new Map<string, string[]>();
	for (const row of rolePermissionsResult.data ?? []) {
		const permissions = rolePermissions.get(row.role) ?? [];
		permissions.push(row.permission_key);
		rolePermissions.set(row.role, permissions);
	}

	const overridesByUser = new Map<string, { permission_key: string; override_state: string }[]>();
	for (const row of overridesResult.data ?? []) {
		const overrides = overridesByUser.get(row.user_id) ?? [];
		overrides.push(row);
		overridesByUser.set(row.user_id, overrides);
	}

	return json({
		organization_id: auth.organization.id,
		actor_user_id: auth.user.id,
		roles: CONTRACTOR_ROLES,
		permissions: permissionsResult.data ?? [],
		members: (membersResult.data ?? []).map((member) => ({
			...member,
			permissions: resolveMemberPermissionMap(
				rolePermissions.get(member.role) ?? [],
				overridesByUser.get(member.user_id) ?? [],
				access.features
			),
			overrides: Object.fromEntries(
				(overridesByUser.get(member.user_id) ?? []).map((override) => [
					override.permission_key,
					override.override_state
				])
			)
		}))
	});
};
