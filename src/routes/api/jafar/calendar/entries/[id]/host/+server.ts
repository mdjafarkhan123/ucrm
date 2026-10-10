import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError, notFound } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { CALLS_REFUSED, calendarViewer, parseBody, visibleCall } from '$lib/server/jafar/calendar';
import { hostChoices } from '$lib/server/jafar/booking-hosts';
import { sendBookingEmail } from '$lib/server/jafar/booking-emails';
import { bookingHostChangeSchema } from '$lib/server/validation/booking.schema';
import type { BookingView, HostChoice, HostChoices } from '$lib/jafar/booking';

// Jafar business management E3: hand a call a visitor booked online to another of its meeting type's hosts, as
// Calendly's reassign does -- only to someone free then (inside their weekly hours, nothing else on their
// calendar), and the visitor is emailed. Anyone who can change calls may do it, as moving the call.

const NOT_FOUND = 'This call was not booked online, or is no longer on the calendar.';

type Client = ReturnType<typeof getOwnerSupabaseClient>;

type Stored = {
	booking: BookingView;
	can_change: boolean;
	choices: { member_id: string | null; name: string; state: HostChoice['state'] }[];
};

/** The call's hosts, a teammate who has since lost Leads & Deals change access shown as such. */
async function choicesFor(client: Client, entryId: string): Promise<HostChoices | null> {
	const { data, error } = await client.rpc('owner_booking_host_choices', {
		target_entry_id: entryId
	});
	if (error) throw error;
	const stored = data as Stored | null;
	if (!stored) return null;
	const qualified = new Set((await hostChoices(client)).map((choice) => choice.id));
	return {
		can_change: stored.can_change,
		host_member_id: stored.booking.host_member_id,
		choices: stored.choices.map((choice) => ({
			...choice,
			state:
				choice.member_id !== null &&
				!qualified.has(choice.member_id) &&
				(choice.state === 'free' || choice.state === 'busy' || choice.state === 'outside_hours')
					? 'no_access'
					: choice.state
		}))
	};
}

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(NOT_FOUND);
	const viewer = calendarViewer(session);
	const client = getOwnerSupabaseClient();
	try {
		if (!(await visibleCall(client, event.params.id, viewer.memberId, viewer.canSeeCalls)))
			return notFound(NOT_FOUND);
		const choices = await choicesFor(client, event.params.id);
		if (!choices) return notFound(NOT_FOUND);
		return json(
			{ ...choices, can_change: choices.can_change && viewer.canWorkCalls },
			{ headers: PRIVATE_READ_HEADERS }
		);
	} catch (error) {
		console.error('Could not load the call’s hosts.', error);
		return json({ error: 'The hosts could not be loaded.' }, { status: 500 });
	}
};

const REFUSALS: Record<string, { status: number; error: string }> = {
	busy: {
		status: 409,
		error: 'They have something else on their calendar then. Choose someone else.'
	},
	outside_hours: {
		status: 409,
		error:
			'That time is outside their weekly hours. Choose someone else, or change their hours first.'
	},
	not_eligible: { status: 409, error: 'They are not a host of this meeting.' },
	closed: { status: 409, error: 'This call is over or closed, so its host cannot change.' },
	retry: { status: 409, error: 'This call changed hands just now. Look again and choose.' }
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(NOT_FOUND);
	const viewer = calendarViewer(session);
	if (!viewer.canWorkCalls) return json({ error: CALLS_REFUSED }, { status: 403 });
	const parsed = await parseBody(event, bookingHostChangeSchema);
	if (!parsed.ok) return parsed.response;
	const memberId = parsed.data.member_id;
	const client = getOwnerSupabaseClient();

	try {
		if (!(await visibleCall(client, event.params.id, viewer.memberId, viewer.canSeeCalls)))
			return notFound(NOT_FOUND);
		if (memberId !== null && !(await hostChoices(client)).some((choice) => choice.id === memberId))
			return json(
				{ error: 'They cannot change Leads & Deals, so they cannot host calls.' },
				{ status: 409 }
			);
		const { data, error } = await client.rpc('owner_booking_change_host', {
			actor_email: session.email,
			target_entry_id: event.params.id,
			target_member_id: memberId as string
		});
		if (error) throw error;
		const result = data as { outcome: string; from_host_name?: string } & BookingView;
		if (result.outcome === 'unknown') return notFound(NOT_FOUND);
		const refusal = REFUSALS[result.outcome];
		if (refusal)
			return json({ error: refusal.error, outcome: result.outcome }, { status: refusal.status });
		if (result.outcome === 'changed') {
			try {
				await sendBookingEmail(
					client,
					result,
					{
						kind: 'host_changed',
						fromHostName: result.from_host_name ?? 'Jafar',
						changeId: crypto.randomUUID()
					},
					event.url.origin
				);
			} catch (emailError) {
				// The change stands; the visitor sees the new host on their link page.
				console.error(
					'Could not queue the email telling the visitor about the new host.',
					emailError
				);
			}
		}
		return json({ ok: true, host_name: result.host_name ?? null });
	} catch (error) {
		console.error('Could not change the call’s host.', error);
		return databaseError();
	}
};
