import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import { PRIVATE_READ_HEADERS, databaseError, unauthorized } from '$lib/server/api/errors';

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
	const list = ids
		.map((id) => ({
			id,
			full_name: byId.get(id)?.full_name ?? null,
			avatar_url: byId.get(id)?.avatar_url ?? null,
			schedule_color: colorById.get(id) ?? null
		}))
		.sort((a, b) => (a.full_name ?? '').localeCompare(b.full_name ?? ''));

	return json({ members: list }, { headers: PRIVATE_READ_HEADERS });
};
