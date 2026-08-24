import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { isContractorRole, requireContractorTeamAdmin } from '$lib/server/access/contractor';
import { teamAccessEditorModel } from '$lib/server/access/team-access-editor';
import { getTeamCommandClient } from '$lib/server/access/team-commands';
import { userIdSchema } from '$lib/server/validation/access.schema';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';

export const GET: RequestHandler = async (event) => {
	const required = await requireContractorTeamAdmin(event);
	if ('response' in required) return required.response;

	const parsedUserId = userIdSchema.safeParse(event.params.userId);
	if (!parsedUserId.success) {
		return json({ error: 'The employee identifier is invalid.' }, { status: 422 });
	}

	const client = getTeamCommandClient();
	const organizationId = required.context.auth.organization.id;
	const [memberResult, rolePermissionsResult, overridesResult] = await Promise.all([
		client
			.from('organization_members')
			.select('role, status, access_revision')
			.eq('organization_id', organizationId)
			.eq('user_id', parsedUserId.data)
			.maybeSingle(),
		client.from('role_permissions').select('role, permission_key'),
		client
			.from('organization_member_permission_overrides')
			.select('permission_key, override_state')
			.eq('organization_id', organizationId)
			.eq('user_id', parsedUserId.data)
	]);

	if (memberResult.error || rolePermissionsResult.error || overridesResult.error) {
		console.error('Could not load the Team access editor.', {
			member: memberResult.error,
			rolePermissions: rolePermissionsResult.error,
			overrides: overridesResult.error
		});
		return json(
			{ error: 'That person’s access could not be loaded.' },
			{ status: 500, headers: PRIVATE_READ_HEADERS }
		);
	}
	if (!memberResult.data) {
		return json(
			{ error: 'That team member was not found.' },
			{ status: 404, headers: PRIVATE_READ_HEADERS }
		);
	}
	if (!isContractorRole(memberResult.data.role)) {
		console.error(
			'Team access editor received an unsupported member role.',
			memberResult.data.role
		);
		return json(
			{ error: 'That person’s access could not be loaded.' },
			{ status: 500, headers: PRIVATE_READ_HEADERS }
		);
	}

	const rolePermissionKeys = new Map<string, Set<string>>();
	for (const row of rolePermissionsResult.data ?? []) {
		const permissions = rolePermissionKeys.get(row.role) ?? new Set<string>();
		permissions.add(row.permission_key);
		rolePermissionKeys.set(row.role, permissions);
	}
	const overrides = new Map(
		(overridesResult.data ?? []).flatMap((row) =>
			row.override_state === 'grant' || row.override_state === 'deny'
				? [[row.permission_key, row.override_state] as const]
				: []
		)
	);

	return json(
		{
			access: teamAccessEditorModel({
				actorRole: required.context.auth.organization.role,
				actorUserId: required.context.auth.user.id,
				targetUserId: parsedUserId.data,
				targetRole: memberResult.data.role,
				targetStatus: memberResult.data.status,
				accessRevision: memberResult.data.access_revision,
				rolePermissionKeys,
				overrides,
				features: required.context.access.features
			})
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
