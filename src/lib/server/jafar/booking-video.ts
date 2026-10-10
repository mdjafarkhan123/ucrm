import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { createOwnerNotification } from '$lib/server/events/outbox';
import { syncZoomMeetings } from '$lib/server/jafar/zoom-sync';
import { VIDEO_PROVIDER_WORDS, dateWords, timeWords, type BookingView } from '$lib/jafar/booking';

// Jafar business management E4a: a booked video call with no joining link yet. Its visitor has been told the
// details will follow (booking-emails.ts); the call's host is asked, on their own bell, to add the link on the call.

/** The time in the host's own zone, as their calendar shows it. */
export async function hostTimeWords(client: SupabaseClient<Database>, startsAt: string) {
	const prefs = await client.rpc('owner_calendar_preferences', {});
	const zone = (prefs.data as { time_zone: string | null } | null)?.time_zone ?? 'UTC';
	return `${dateWords(startsAt, zone, 'en-GB')} at ${timeWords(startsAt, zone, 'en-GB')}`;
}

export async function askHostForVideoLink(client: SupabaseClient<Database>, booking: BookingView) {
	if (booking.location_kind === 'phone' || booking.video_join_url) return;
	const provider = VIDEO_PROVIDER_WORDS[booking.location_kind];
	await createOwnerNotification(client, {
		kind: 'sales_call_video_link_needed',
		severity: 'attention',
		title: `Add the ${provider} link for ${booking.business_name}'s call`,
		body: `${booking.visitor_name}'s ${booking.name} is ${await hostTimeWords(client, booking.starts_at)}. They have been told the joining link will follow by email. Open the call on the calendar to add it.`,
		target: { targetKind: 'business_relationship', targetId: booking.relationship_id },
		recipientMemberId: booking.host_member_id
	});
}

/**
 * E4b: does the Zoom work this booking is owed (a meeting made, moved or deleted) and returns its view as it now
 * stands, so the email and page that follow say the truth. Nothing here can fail the booking.
 */
export async function withZoomMeeting<T extends BookingView>(
	client: SupabaseClient<Database>,
	booking: T
): Promise<BookingView> {
	if (booking.location_kind === 'phone' || !booking.entry_id) return booking;
	try {
		await syncZoomMeetings(client, booking.booking_id);
		const { data, error } = await client.rpc('owner_booking_for_entry', {
			target_entry_id: booking.entry_id
		});
		if (error) throw error;
		return (data as BookingView | null) ?? booking;
	} catch (error) {
		console.error('Could not refresh a booking after its Zoom meeting.', error);
		return booking;
	}
}
