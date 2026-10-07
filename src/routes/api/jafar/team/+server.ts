import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordPlatformAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getServerEnv } from '$lib/server/env';
import { TeamMemberError, inviteTeamMember, listTeamMembers } from '$lib/server/jafar/team-members';
import { teamInviteSchema } from '$lib/server/validation/team-member.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

// Jafar's team (D1, ADR 0008). Only the owner manages teammates; the front-door gate already refuses a
// teammate here, and the role check repeats it.

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session || session.role !== null) return ownerUnauthorized();

	try {
		return json({ members: await listTeamMembers(getOwnerSupabaseClient()) });
	} catch (error) {
		console.error('Could not load the team.', error);
		return json({ error: 'Your team could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session || session.role !== null) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = teamInviteSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the highlighted fields.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	const client = getOwnerSupabaseClient();
	try {
		const member = await inviteTeamMember(client, {
			email: parsed.data.email,
			role: parsed.data.role,
			invitedBy: session.email,
			origin: event.url.origin,
			ownerEmail: getServerEnv().SUPER_ADMIN_EMAIL
		});
		await recordPlatformAudit(client, {
			email: session.email,
			event_type: 'team_member_invited',
			target_type: 'platform_team_member',
			target_key: member.id,
			after_state: { email: member.email, role: member.role }
		});
		return json({ member }, { status: 201 });
	} catch (error) {
		if (error instanceof TeamMemberError) {
			const status = error.code === 'email_failed' ? 502 : 409;
			return json(
				{
					error: error.message,
					code: error.code,
					...(status === 409 ? { field_errors: { email: error.message } } : {})
				},
				{ status }
			);
		}
		console.error('Could not invite a teammate.', error);
		return json({ error: 'The invitation could not be sent. Try again.' }, { status: 500 });
	}
};
