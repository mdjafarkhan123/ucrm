import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordPlatformAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { TeamMemberError, removeTeamMember } from '$lib/server/jafar/team-members';

// Removes a teammate, signing them out at once, or cancels a waiting invitation (D1, ADR 0008).
export const DELETE: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session || session.role !== null) return ownerUnauthorized();

	const memberId = z.string().uuid().safeParse(event.params.memberId);
	if (!memberId.success)
		return json({ error: 'That teammate could not be found.' }, { status: 404 });

	const client = getOwnerSupabaseClient();
	try {
		const member = await removeTeamMember(client, {
			memberId: memberId.data,
			removedBy: session.email
		});
		await recordPlatformAudit(client, {
			email: session.email,
			event_type: member.status === 'invited' ? 'team_invitation_cancelled' : 'team_member_removed',
			target_type: 'platform_team_member',
			target_key: member.id,
			before_state: { email: member.email, role: member.role, status: member.status }
		});
		return json({ ok: true });
	} catch (error) {
		if (error instanceof TeamMemberError) return json({ error: error.message }, { status: 404 });
		console.error('Could not remove a teammate.', error);
		return json({ error: 'The teammate could not be removed. Try again.' }, { status: 500 });
	}
};
