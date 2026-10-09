import type { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	TEAM_ROLES,
	effectiveTeamAccess,
	storedTeamAccessAdjustments,
	type AreaLevel,
	type JafarArea,
	type TeamRole
} from '$lib/jafar/team-access';
import type { SetupOwnerChoice } from '$lib/jafar/deals';

type Client = ReturnType<typeof getOwnerSupabaseClient>;

/**
 * The active teammates who can be handed work in an area, by name: whoever's access opens it, at `work` when
 * they must be able to change things there. Jafar is always a choice too; the pickers add him.
 */
export async function teammatesWhoCan(
	client: Client,
	area: JafarArea,
	level: AreaLevel = 'look'
): Promise<SetupOwnerChoice[]> {
	const { data, error } = await client
		.from('platform_team_members')
		.select('id, email, full_name, avatar_url, role, area_adjustments, action_grants')
		.eq('status', 'active')
		.is('removed_at', null);
	if (error) throw error;
	return (data ?? [])
		.filter((member) => {
			if (!TEAM_ROLES.includes(member.role as TeamRole)) return false;
			const open = effectiveTeamAccess(
				member.role as TeamRole,
				storedTeamAccessAdjustments(member.area_adjustments, member.action_grants)
			).areas[area];
			return level === 'work' ? open === 'work' : Boolean(open);
		})
		.map((member) => ({
			id: member.id,
			name: member.full_name || member.email,
			avatar_url: member.avatar_url
		}))
		.sort((a, b) => a.name.localeCompare(b.name));
}
