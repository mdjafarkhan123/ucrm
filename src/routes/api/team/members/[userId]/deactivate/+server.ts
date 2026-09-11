import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import {
	getTeamCommandClient,
	teamCommandErrorResponse,
	teamMemberSummary
} from '$lib/server/access/team-commands';
import { userIdSchema, zodAccessFieldErrors } from '$lib/server/validation/access.schema';

// Who may deactivate whom, and unassigning their incomplete assessments/visits/tasks, all live inside
// deactivate_team_member. This route only checks that the caller is a team manager and that the target id
// is shaped right, then gets out of the way.
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
		.rpc('deactivate_team_member', {
			target_organization_id: auth.organization.id,
			actor_user_id: auth.user.id,
			target_user_id: parsedUserId.data
		})
		.single();

	if (error) return teamCommandErrorResponse(error, 'That person could not be deactivated.');

	return json({ member: teamMemberSummary(member) });
};
