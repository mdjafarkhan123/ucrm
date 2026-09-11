import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import {
	getTeamCommandClient,
	teamCommandErrorResponse,
	teamMemberSummary
} from '$lib/server/access/team-commands';
import { userIdSchema, zodAccessFieldErrors } from '$lib/server/validation/access.schema';

// Who may permanently remove whom -- owner-only, already deactivated, no administrator without a prior
// demotion -- all live inside remove_team_member. This route only checks that the caller is a team
// manager and that the target id is shaped right, then gets out of the way, same as deactivate/restore.
export const POST: RequestHandler = async (event) => {
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

	const { auth } = required.context;
	const { data: member, error } = await getTeamCommandClient()
		.rpc('remove_team_member', {
			target_organization_id: auth.organization.id,
			actor_user_id: auth.user.id,
			target_user_id: parsedUserId.data
		})
		.single();

	if (error)
		return teamCommandErrorResponse(error, 'That person could not be permanently removed.');

	return json({ member: teamMemberSummary(member) });
};
