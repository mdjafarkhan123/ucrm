import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import {
	getTeamCommandClient,
	teamCommandErrorResponse,
	teamMemberSummary
} from '$lib/server/access/team-commands';
import { userIdSchema, zodAccessFieldErrors } from '$lib/server/validation/access.schema';

// restore_team_member is the one seat authority: it blocks the write itself when the organization has no
// free seat, rather than trusting a count this route read a moment earlier.
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
		.rpc('restore_team_member', {
			target_organization_id: auth.organization.id,
			actor_user_id: auth.user.id,
			target_user_id: parsedUserId.data
		})
		.single();

	if (error) return teamCommandErrorResponse(error, 'That person could not be restored.');

	return json({ member: teamMemberSummary(member) });
};
