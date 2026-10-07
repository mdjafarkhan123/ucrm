import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordPlatformAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { TeamMemberError, resendTeamInvitation } from '$lib/server/jafar/team-members';

// A fresh invitation link with seven more days; the old link stops working (D1, ADR 0008). No request body.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session || session.role !== null) return ownerUnauthorized();

	const memberId = z.string().uuid().safeParse(event.params.memberId);
	if (!memberId.success)
		return json({ error: 'That invitation could not be found.' }, { status: 404 });

	const client = getOwnerSupabaseClient();
	try {
		const member = await resendTeamInvitation(client, {
			memberId: memberId.data,
			origin: event.url.origin
		});
		await recordPlatformAudit(client, {
			email: session.email,
			event_type: 'team_invitation_resent',
			target_type: 'platform_team_member',
			target_key: member.id
		});
		return json({ member });
	} catch (error) {
		if (error instanceof TeamMemberError) {
			return json({ error: error.message }, { status: error.code === 'email_failed' ? 502 : 404 });
		}
		console.error('Could not resend a team invitation.', error);
		return json({ error: 'The invitation could not be resent. Try again.' }, { status: 500 });
	}
};
