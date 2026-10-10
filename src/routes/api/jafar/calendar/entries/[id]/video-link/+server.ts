import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError, notFound } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { CALLS_REFUSED, calendarViewer, parseBody, visibleCall } from '$lib/server/jafar/calendar';
import { sendBookingEmail } from '$lib/server/jafar/booking-emails';
import { videoLinkSchema } from '$lib/server/validation/booking.schema';
import type { BookingView, CallVideoLink } from '$lib/jafar/booking';

// Jafar business management E4a: a video call a visitor booked online, and its joining link. The host adds the link
// when the meeting type is in custom-link mode (or UCRM could not make one), or replaces it; the visitor is emailed
// the link. Anyone who can change calls may do it, as moving the call. Phone calls and calls staff booked show
// nothing here.

const NOT_FOUND = 'This call is not a video call booked online, or is no longer on the calendar.';

type Client = ReturnType<typeof getOwnerSupabaseClient>;

function linkOf(booking: BookingView, canWorkCalls: boolean): CallVideoLink | null {
	if (booking.location_kind === 'phone') return null;
	return {
		location_kind: booking.location_kind,
		video_join_url: booking.video_join_url,
		video_link_source: booking.video_link_source,
		can_change:
			canWorkCalls &&
			booking.status === 'booked' &&
			booking.call_status === 'scheduled' &&
			Date.parse(booking.ends_at) > Date.now()
	};
}

async function bookingOf(client: Client, entryId: string) {
	const { data, error } = await client.rpc('owner_booking_for_entry', { target_entry_id: entryId });
	if (error) throw error;
	return data as BookingView | null;
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
		const booking = await bookingOf(client, event.params.id);
		const link = booking && linkOf(booking, viewer.canWorkCalls);
		if (!link) return notFound(NOT_FOUND);
		return json(link, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not load the call’s video link.', error);
		return json({ error: 'The video link could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(NOT_FOUND);
	const viewer = calendarViewer(session);
	if (!viewer.canWorkCalls) return json({ error: CALLS_REFUSED }, { status: 403 });
	const parsed = await parseBody(event, videoLinkSchema);
	if (!parsed.ok) return parsed.response;
	const client = getOwnerSupabaseClient();

	try {
		if (!(await visibleCall(client, event.params.id, viewer.memberId, viewer.canSeeCalls)))
			return notFound(NOT_FOUND);
		const { data, error } = await client.rpc('owner_booking_set_video_link', {
			target_entry_id: event.params.id,
			target_url: parsed.data.url
		});
		if (error) throw error;
		const result = data as { outcome: string; replaced_url?: string | null } & BookingView;
		if (result.outcome === 'unknown' || result.outcome === 'phone') return notFound(NOT_FOUND);
		if (result.outcome === 'closed')
			return json(
				{ error: 'This call is over or cancelled, so its link cannot change.' },
				{ status: 409 }
			);
		if (result.outcome === 'set') {
			try {
				await sendBookingEmail(
					client,
					result,
					{ kind: 'video_link', replaced: Boolean(result.replaced_url) },
					event.url.origin
				);
			} catch (emailError) {
				// The link stands; the visitor also sees it on their booking page and in later emails.
				console.error('Could not queue the email with the joining link.', emailError);
			}
		}
		return json(linkOf(result, viewer.canWorkCalls));
	} catch (error) {
		console.error('Could not save the call’s video link.', error);
		return databaseError();
	}
};
