import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import { PRIVATE_READ_HEADERS, databaseError, unauthorized } from '$lib/server/api/errors';
import { getTeamCommandClient } from '$lib/server/access/team-commands';

// Who can be put on a visit. `/api/team/members` answers a different question — it is the team-admin
// screen's route and carries every permission override with it. Assigning an assessment only needs the
// names, and any member may do it, so this stays deliberately thin.
//
// A team fits on one screen, so there is no pagination here. The cap is a guard against a runaway
// organization, not a page size.
const MAX_MEMBERS = 200;

export const GET: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const supabase = event.locals.supabase;
	const { data: members, error } = await supabase
		.from('organization_members')
		.select('user_id, schedule_color')
		.eq('organization_id', auth.organization.id)
		// Removed and deactivated people can no longer do the work, so they are not offered for it.
		.in('status', ['pending', 'active'])
		.limit(MAX_MEMBERS);
	if (error) return databaseError();

	const ids = (members ?? []).map((member) => member.user_id);
	// The calendar colour is the member's own, not the profile's, so it comes off the membership row.
	const colorById = new Map(
		(members ?? []).map((member) => [member.user_id, member.schedule_color])
	);
	if (ids.length === 0) return json({ members: [] }, { headers: PRIVATE_READ_HEADERS });

	// RLS on profiles only returns people who share an organization with the caller, so this cannot reach
	// beyond the team even if the id list were wrong.
	const { data: profiles, error: profilesError } = await supabase
		.from('profiles')
		.select('id, full_name, avatar_url')
		.in('id', ids);
	if (profilesError) return databaseError();

	const byId = new Map((profiles ?? []).map((profile) => [profile.id, profile]));
	// Someone who accepted an invitation without giving a name would otherwise show as a blank row, and
	// several of them are indistinguishable. profiles carries no email, so their sign-in email comes from
	// auth.users -- only for the unnamed few, the same lookup and degrade-to-null the Team detail uses.
	const unnamed = ids.filter((id) => !byId.get(id)?.full_name);
	const emailById = new Map(
		await Promise.all(unnamed.map(async (id) => [id, await resolveSignInEmail(id)] as const))
	);
	const list = ids
		.map((id) => ({
			id,
			full_name: byId.get(id)?.full_name ?? emailById.get(id) ?? null,
			avatar_url: byId.get(id)?.avatar_url ?? null,
			schedule_color: colorById.get(id) ?? null
		}))
		.sort((a, b) => (a.full_name ?? '').localeCompare(b.full_name ?? ''));

	return json({ members: list }, { headers: PRIVATE_READ_HEADERS });
};

async function resolveSignInEmail(userId: string) {
	try {
		const { data, error } = await getTeamCommandClient().auth.admin.getUserById(userId);
		if (error) throw error;
		return data.user?.email ?? null;
	} catch (error) {
		console.error(`Could not resolve the sign-in email for team member ${userId}.`, error);
		return null;
	}
}
