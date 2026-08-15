import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

export const GET: RequestHandler = async (event) => {
	if (!await getOwnerSession(event)) return ownerUnauthorized();
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

		const [profilesResult, overridesResult] = await Promise.all([
			userIds.length
				? client.from('profiles').select('id, full_name').in('id', userIds)
				: Promise.resolve({ data: [], error: null }),
			userIds.length
				? client
						.from('organization_member_permission_overrides')
						.select('user_id, permission_key, override_state')
						.eq('organization_id', parsedId.data)
				: Promise.resolve({ data: [], error: null })
		]);
		if (profilesResult.error) throw profilesResult.error;
		if (overridesResult.error) throw overridesResult.error;

		const nameByUserId = new Map(
			(profilesResult.data ?? []).map((profile) => [profile.id, profile.full_name])
		);

		const overridesByUserId = new Map<
			string,
			Array<{ permission_key: string; override_state: string }>
		>();
		for (const override of overridesResult.data ?? []) {
			const list = overridesByUserId.get(override.user_id) ?? [];
			list.push({ permission_key: override.permission_key, override_state: override.override_state });
			overridesByUserId.set(override.user_id, list);
		}

		// A single member's admin-API lookup failing (seen for legacy-imported accounts) must not
		// take down the whole team list -- degrade that member's email to null instead of 500ing.
		const emailEntries = await Promise.all(
			userIds.map(async (userId) => {
				try {
					const { data, error } = await client.auth.admin.getUserById(userId);
					if (error) throw error;
					return [userId, data.user?.email ?? null] as const;
				} catch (error) {
					console.error(`Could not resolve auth email for team member ${userId}.`, error);
					return [userId, null] as const;
				}
			})
		);
		const emailByUserId = new Map(emailEntries);

		const teamMembers = memberRows.map((member) => ({
			user_id: member.user_id,
			role: member.role,
			created_at: member.created_at,
			full_name: nameByUserId.get(member.user_id) ?? null,
			email: emailByUserId.get(member.user_id) ?? null,
			permission_overrides: overridesByUserId.get(member.user_id) ?? []
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
