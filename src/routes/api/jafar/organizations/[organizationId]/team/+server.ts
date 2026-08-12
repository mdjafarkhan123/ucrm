import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

export const GET: RequestHandler = async (event) => {
	if (!getOwnerSession(event)) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	const client = getOwnerSupabaseClient();

	try {
		const { data: organization, error: organizationError } = await client
			.from('organizations')
			.select('id, name')
			.eq('id', parsedId.data)
			.maybeSingle();
		if (organizationError) throw organizationError;
		if (!organization) return json({ error: 'Organization was not found.' }, { status: 404 });

		const { data: members, error: membersError } = await client
			.from('organization_members')
			.select('user_id, role, created_at')
			.eq('organization_id', parsedId.data)
			.order('created_at', { ascending: true });
		if (membersError) throw membersError;

		const memberRows = members ?? [];
		const userIds = memberRows.map((member) => member.user_id);

		const { data: profiles, error: profilesError } = userIds.length
			? await client.from('profiles').select('id, full_name').in('id', userIds)
			: { data: [], error: null };
		if (profilesError) throw profilesError;

		const nameByUserId = new Map(
			(profiles ?? []).map((profile) => [profile.id, profile.full_name])
		);
		const emailEntries = await Promise.all(
			userIds.map(async (userId) => {
				const { data, error } = await client.auth.admin.getUserById(userId);
				if (error) throw error;
				return [userId, data.user?.email ?? null] as const;
			})
		);
		const emailByUserId = new Map(emailEntries);

		const teamMembers = memberRows.map((member) => ({
			user_id: member.user_id,
			role: member.role,
			created_at: member.created_at,
			full_name: nameByUserId.get(member.user_id) ?? null,
			email: emailByUserId.get(member.user_id) ?? null
		}));

		const hasAdministrator = teamMembers.some(
			(member) => member.role === 'owner' || member.role === 'admin'
		);

		return json({ organization, members: teamMembers, has_administrator: hasAdministrator });
	} catch (error) {
		console.error('Could not load organization team.', error);
		return json({ error: 'Team members could not be loaded.' }, { status: 500 });
	}
};
