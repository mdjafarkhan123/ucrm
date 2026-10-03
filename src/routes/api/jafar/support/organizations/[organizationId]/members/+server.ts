import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import type { SupportRecipient } from '$lib/support/api';

// A business's active team, owner first, then admins, then everyone else by name: who Uplift may start a
// chat with (D5a). A team is tens of people; the cap only guards against the unexpected.
const ROLE_ORDER = ['owner', 'admin'];
const MAX_MEMBERS = 200;

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const organizationId = z.string().uuid().safeParse(event.params.organizationId);
	if (!organizationId.success)
		return json({ error: 'That business could not be found.' }, { status: 404 });

	const client = getOwnerSupabaseClient();
	try {
		const { data: organization, error: organizationError } = await client
			.from('organizations')
			.select('id, name')
			.eq('id', organizationId.data)
			.maybeSingle();
		if (organizationError) throw organizationError;
		if (!organization) return json({ error: 'That business could not be found.' }, { status: 404 });

		const { data: members, error } = await client
			.from('organization_members')
			.select('user_id, role')
			.eq('organization_id', organizationId.data)
			.eq('status', 'active')
			.limit(MAX_MEMBERS);
		if (error) throw error;

		const ids = members.map((member) => member.user_id);
		const { data: profiles, error: profilesError } = ids.length
			? await client.from('profiles').select('id, full_name').in('id', ids)
			: { data: [], error: null };
		if (profilesError) throw profilesError;

		const names = new Map(profiles.map((profile) => [profile.id, profile.full_name]));
		const rank = (role: string) => {
			const index = ROLE_ORDER.indexOf(role);
			return index === -1 ? ROLE_ORDER.length : index;
		};
		const result: SupportRecipient[] = members
			.map((member) => ({
				user_id: member.user_id,
				name: names.get(member.user_id) || 'Team member',
				role: member.role
			}))
			.sort(
				(first, second) =>
					rank(first.role) - rank(second.role) || first.name.localeCompare(second.name)
			);

		return json({ organization, members: result });
	} catch (error) {
		console.error('Could not read a business team for a support chat.', error);
		return json({ error: "This business's team could not be loaded." }, { status: 500 });
	}
};
