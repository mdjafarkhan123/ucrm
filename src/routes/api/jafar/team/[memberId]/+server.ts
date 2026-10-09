import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordPlatformAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { TeamMemberError, removeTeamMember } from '$lib/server/jafar/team-members';
import { sendBookingEmail } from '$lib/server/jafar/booking-emails';
import type { BookingView } from '$lib/jafar/booking';

type Client = ReturnType<typeof getOwnerSupabaseClient>;

/** E3: the visitor-booked calls a teammate hosts, read before removal hands them back to Jafar. */
async function hostedCalls(client: Client, memberId: string) {
	const { data, error } = await client.rpc('owner_booking_hosted_calls', {
		target_member_id: memberId
	});
	if (error) throw error;
	return (data ?? []).map((row) => row.entry_id);
}

/** E3: tells each of those visitors their call is now with Jafar (Jafar, 2026-10-09). The removal stands. */
async function tellVisitors(client: Client, entryIds: string[], fromHostName: string, origin: string) {
	for (const entryId of entryIds) {
		try {
			const { data, error } = await client.rpc('owner_booking_for_entry', {
				target_entry_id: entryId
			});
			if (error) throw error;
			const booking = data as BookingView | null;
			if (!booking || booking.host_member_id !== null) continue;
			await sendBookingEmail(
				client,
				booking,
				{ kind: 'host_changed', fromHostName, changeId: `removed:${entryId}` },
				origin
			);
		} catch (error) {
			console.error('Could not queue the email telling a visitor their call is now with Jafar.', error);
		}
	}
}

// Removes a teammate, signing them out at once, or cancels a waiting invitation (D1, ADR 0008). E3: the calls
// prospects booked with them come back to Jafar, and each prospect is emailed.
export const DELETE: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session || session.role !== null) return ownerUnauthorized();

	const memberId = z.string().uuid().safeParse(event.params.memberId);
	if (!memberId.success)
		return json({ error: 'That teammate could not be found.' }, { status: 404 });

	const client = getOwnerSupabaseClient();
	try {
		const calls = await hostedCalls(client, memberId.data);
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
		await tellVisitors(client, calls, member.full_name ?? member.email, event.url.origin);
		return json({ ok: true });
	} catch (error) {
		if (error instanceof TeamMemberError) return json({ error: error.message }, { status: 404 });
		console.error('Could not remove a teammate.', error);
		return json({ error: 'The teammate could not be removed. Try again.' }, { status: 500 });
	}
};
