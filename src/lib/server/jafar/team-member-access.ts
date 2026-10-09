import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Json } from '$lib/database.types';
import {
	TEAM_ROLES,
	adjustmentsFor,
	effectiveTeamAccess,
	storedTeamAccessAdjustments,
	teamAccessProblem,
	type TeamAccess,
	type TeamRole
} from '$lib/jafar/team-access';
import type { TeamAccessHistoryEntry, TeamMemberAccessView } from '$lib/jafar/team';

/**
 * One teammate's access in the Jafar Panel (D2, ADR 0008): what they can open now, the adjustments behind
 * it, and the history of who changed it. Saving goes through `platform_team_set_access`, which refuses a
 * stale revision and writes the history row in the same transaction.
 */

type Client = SupabaseClient<Database>;

const HISTORY_LIMIT = 30;

export type TeamAccessErrorCode = 'not_found' | 'stale' | 'invalid';

export class TeamAccessError extends Error {
	constructor(
		public readonly code: TeamAccessErrorCode,
		message: string
	) {
		super(message);
		this.name = 'TeamAccessError';
	}
}

const NOT_FOUND_MESSAGE = 'That teammate could not be found. They may have been removed.';

export async function getTeamMemberAccess(
	client: Client,
	memberId: string
): Promise<TeamMemberAccessView> {
	const [memberResult, historyResult] = await Promise.all([
		client
			.from('platform_team_members')
			.select(
				'id, email, full_name, role, status, access_revision, area_adjustments, action_grants'
			)
			.eq('id', memberId)
			.neq('status', 'removed')
			.maybeSingle(),
		client
			.from('platform_audit_events')
			.select('id, event_type, actor_owner_email, created_at, before_state, after_state')
			.eq('target_type', 'platform_team_member')
			.eq('target_key', memberId)
			.order('created_at', { ascending: false })
			.limit(HISTORY_LIMIT)
	]);
	if (memberResult.error) throw memberResult.error;
	if (historyResult.error) throw historyResult.error;

	const member = memberResult.data;
	if (!member || !(TEAM_ROLES as readonly string[]).includes(member.role)) {
		throw new TeamAccessError('not_found', NOT_FOUND_MESSAGE);
	}
	const role = member.role as TeamRole;
	const adjustments = storedTeamAccessAdjustments(member.area_adjustments, member.action_grants);

	return {
		member: {
			id: member.id,
			email: member.email,
			full_name: member.full_name,
			role,
			status: member.status as TeamMemberAccessView['member']['status'],
			access_revision: member.access_revision
		},
		adjustments,
		access: effectiveTeamAccess(role, adjustments),
		history: (historyResult.data ?? []).map((event): TeamAccessHistoryEntry => ({
			id: event.id,
			event_type: event.event_type,
			actor_email: event.actor_owner_email,
			created_at: event.created_at,
			before_state: event.before_state,
			after_state: event.after_state
		}))
	};
}

/**
 * Saves the role and the access Jafar chose. Only what differs from the role is stored, so a later change
 * to a role's starting access still reaches teammates who were not adjusted there.
 */
export async function saveTeamMemberAccess(
	client: Client,
	params: {
		memberId: string;
		role: TeamRole;
		access: TeamAccess;
		expectedRevision: number;
		actorEmail: string;
	}
): Promise<TeamMemberAccessView> {
	const problem = teamAccessProblem(params.access);
	if (problem) throw new TeamAccessError('invalid', problem);

	const adjustments = adjustmentsFor(params.role, params.access);
	const { data, error } = await client.rpc('platform_team_set_access', {
		p_member_id: params.memberId,
		p_expected_revision: params.expectedRevision,
		p_role: params.role,
		p_area_adjustments: adjustments.areas as Json,
		p_action_grants: adjustments.actions,
		p_actor_email: params.actorEmail
	});
	if (error) throw error;

	if (!data?.length) {
		// Nothing saved: either the teammate is gone or someone saved a newer version first.
		const current = await getTeamMemberAccess(client, params.memberId);
		throw new TeamAccessError(
			'stale',
			`${current.member.full_name ?? current.member.email}’s access changed while you were editing. Reload to see the latest.`
		);
	}

	return getTeamMemberAccess(client, params.memberId);
}
