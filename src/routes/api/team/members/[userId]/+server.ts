import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import {
	getTeamCommandClient,
	teamCommandErrorResponse,
	teamMemberSummary
} from '$lib/server/access/team-commands';
import {
	memberRoleChangeSchema,
	userIdSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';

const teamMemberDetailSchema = z.object({
	user_id: z.uuid(),
	display_name: z.string().nullable(),
	avatar_url: z.string().nullable(),
	role: z.enum(['owner', 'admin', 'office', 'sales', 'field', 'finance']),
	status: z.enum(['pending', 'active', 'deactivated']),
	access_revision: z.number().int().nonnegative(),
	profile_revision: z.number().int().nonnegative(),
	work_phone: z.string().nullable(),
	job_title: z.string().nullable(),
	schedule_color: z.string().nullable(),
	created_at: z.string(),
	deactivated_at: z.string().nullable(),
	invitation: z
		.object({
			id: z.uuid(),
			email: z.string().email(),
			state: z.enum(['reserving', 'invited', 'accepting']),
			delivery_failed: z.boolean(),
			last_sent_at: z.string().nullable(),
			expires_at: z.string()
		})
		.nullable()
});

function invalidMemberResponse() {
	return json(
		{ error: 'The employee identifier is invalid.' },
		{ status: 422, headers: PRIVATE_READ_HEADERS }
	);
}

export const GET: RequestHandler = async (event) => {
	const required = await requireContractorTeamAdmin(event);
	if ('response' in required) return required.response;

	const parsedUserId = userIdSchema.safeParse(event.params.userId);
	if (!parsedUserId.success) return invalidMemberResponse();

	const { data, error } = await event.locals.supabase.rpc('get_team_member_detail', {
		target_organization_id: required.context.auth.organization.id,
		target_user_id: parsedUserId.data
	});
	if (error?.code === 'P0002') {
		return json(
			{ error: 'That team member was not found.' },
			{ status: 404, headers: PRIVATE_READ_HEADERS }
		);
	}
	const member = teamMemberDetailSchema.safeParse(data);
	if (error || !member.success) {
		console.error('Could not load the Team member detail.', error);
		return json(
			{ error: 'That team member could not be loaded.' },
			{ status: 500, headers: PRIVATE_READ_HEADERS }
		);
	}

	return json({ member: member.data }, { headers: PRIVATE_READ_HEADERS });
};

// Who may change whose role, whether the organization keeps an owner, and which individual adjustments
// survive the move are all decided by change_team_member_role. This route checks that the caller is a
// team manager here at all, checks the shape of what they sent, and then gets out of the way -- the
// rules used to be spelled out twice, and two copies of a rule is one rule waiting to disagree.
export const PATCH: RequestHandler = async (event) => {
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

	const parsed = memberRoleChangeSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the requested role.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	const { auth } = required.context;
	const { data: member, error } = await getTeamCommandClient()
		.rpc('change_team_member_role', {
			target_organization_id: auth.organization.id,
			actor_user_id: auth.user.id,
			target_user_id: parsedUserId.data,
			new_role: parsed.data.role,
			keep_adjustments: parsed.data.keep_adjustments,
			expected_access_revision: parsed.data.expected_access_revision
		})
		.single();

	if (error) return teamCommandErrorResponse(error, 'The employee role could not be changed.');

	return json({ member: teamMemberSummary(member) });
};
