import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import {
	getTeamCommandClient,
	teamCommandErrorResponse,
	teamMemberSummary
} from '$lib/server/access/team-commands';
import {
	isTeamAccessControlId,
	isTeamAccessPermissionKey,
	permissionKeyForTeamAccessControl
} from '$lib/server/access/team-access-editor';
import {
	memberPermissionsSaveSchema,
	userIdSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';

// One save for the whole adjustment section, replacing the old one-request-per-control route. The screen
// saves a section, and save_team_member_permissions can see the before and the after together, so the
// history gets one line saying what actually moved instead of a line per checkbox.
export const PUT: RequestHandler = async (event) => {
	const required = await requireContractorTeamAdmin(event);
	if ('response' in required) return required.response;

	const parsedUserId = userIdSchema.safeParse(event.params.userId);
	if (!parsedUserId.success) {
		return json(
			{
				error: 'The employee identifier is invalid.',
				field_errors: zodAccessFieldErrors(parsedUserId.error)
			},
			{ status: 422 }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = memberPermissionsSaveSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the requested permission adjustments.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}
	const desiredOverrides = parsed.data.adjustments.flatMap((adjustment) => {
		if (!isTeamAccessControlId(adjustment.control_id)) return [];
		const permissionKey = permissionKeyForTeamAccessControl(adjustment.control_id);
		return permissionKey
			? [{ permission_key: permissionKey, override_state: adjustment.override_state }]
			: [];
	});
	if (desiredOverrides.length !== parsed.data.adjustments.length) {
		return json(
			{
				error: 'Please review the requested permission adjustments.',
				field_errors: { adjustments: 'One of those access controls is not available.' }
			},
			{ status: 422 }
		);
	}

	const { auth } = required.context;
	const commandClient = getTeamCommandClient();
	const { data: existingOverrides, error: existingOverridesError } = await commandClient
		.from('organization_member_permission_overrides')
		.select('permission_key, override_state')
		.eq('organization_id', auth.organization.id)
		.eq('user_id', parsedUserId.data);
	if (existingOverridesError) {
		console.error(
			'Could not preserve unavailable Team permission adjustments.',
			existingOverridesError
		);
		return json({ error: 'The permission adjustments could not be saved.' }, { status: 500 });
	}
	const preservedOverrides = (existingOverrides ?? []).flatMap((override) =>
		isTeamAccessPermissionKey(override.permission_key) ||
		(override.override_state !== 'grant' && override.override_state !== 'deny')
			? []
			: [{ permission_key: override.permission_key, override_state: override.override_state }]
	);
	const { data: member, error } = await commandClient
		.rpc('save_team_member_permissions', {
			target_organization_id: auth.organization.id,
			actor_user_id: auth.user.id,
			target_user_id: parsedUserId.data,
			desired_overrides: [...preservedOverrides, ...desiredOverrides],
			expected_access_revision: parsed.data.expected_access_revision
		})
		.single();

	if (error) {
		return teamCommandErrorResponse(error, 'The permission adjustments could not be saved.');
	}

	return json({ member: teamMemberSummary(member), adjustments: parsed.data.adjustments });
};
