import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { sendBookingEmail } from '$lib/server/jafar/booking-emails';
import {
	ZoomError,
	createZoomMeeting,
	deleteZoomMeeting,
	moveZoomMeeting,
	zoomConfigured
} from '$lib/server/jafar/zoom';
import type { BookingView } from '$lib/jafar/booking';

// Jafar business management E4b: keeps each booking's Zoom meeting in step with the booking. The database says what
// is owed (owner_booking_zoom_work: make, move or delete); this does it. A booking change runs it for that booking
// straight away, and the worker's sweep runs it for every booking, so a Zoom outage only delays a meeting -- the
// visitor is told the details will follow until it exists (E4a), and the sweep sends the link when it does.

type Client = SupabaseClient<Database>;

type Work = {
	booking_id: string;
	entry_id: string | null;
	action: 'create' | 'update' | 'delete';
	meeting_id: string | null;
	starts_at: string | null;
	ends_at: string | null;
	topic: string;
};

export type ZoomSyncResult = {
	made: { booking_id: string; entry_id: string | null }[];
	failed: string[];
};

async function made(client: Client, work: Work) {
	if (!work.starts_at || !work.ends_at) return false;
	const meeting = await createZoomMeeting(client, {
		topic: work.topic,
		startsAt: work.starts_at,
		endsAt: work.ends_at
	});
	// A link the host pasted in the meantime wins: only a booking still without one takes the new meeting.
	const { data, error } = await client
		.from('platform_bookings')
		.update({
			video_join_url: meeting.joinUrl,
			video_link_source: 'provider',
			video_provider_meeting_id: meeting.meetingId,
			video_link_set_at: new Date().toISOString(),
			video_synced_starts_at: work.starts_at
		})
		.eq('id', work.booking_id)
		.is('video_join_url', null)
		.select('id');
	if (error || !data?.length) {
		await deleteZoomMeeting(client, meeting.meetingId).catch((cleanup) =>
			console.error('Could not remove a Zoom meeting that was not used.', cleanup)
		);
		if (error) throw error;
		return false;
	}
	return true;
}

async function run(client: Client, work: Work) {
	if (work.action === 'create') return made(client, work);
	if (!work.meeting_id) return false;
	if (work.action === 'update') {
		if (!work.starts_at || !work.ends_at) return false;
		await moveZoomMeeting(client, work.meeting_id, {
			topic: work.topic,
			startsAt: work.starts_at,
			endsAt: work.ends_at
		});
		const { error } = await client
			.from('platform_bookings')
			.update({ video_synced_starts_at: work.starts_at })
			.eq('id', work.booking_id)
			.eq('video_provider_meeting_id', work.meeting_id);
		if (error) throw error;
		return false;
	}
	await deleteZoomMeeting(client, work.meeting_id);
	const { error } = await client
		.from('platform_bookings')
		.update({
			video_join_url: null,
			video_link_source: null,
			video_provider_meeting_id: null,
			video_link_set_at: null,
			video_synced_starts_at: null
		})
		.eq('id', work.booking_id)
		.eq('video_provider_meeting_id', work.meeting_id);
	if (error) throw error;
	return false;
}

/**
 * Does the Zoom work owed to one booking, or to every booking when none is named. Never throws: a failure is logged
 * and left for the next sweep. `made` lists the bookings that just got a meeting.
 */
export async function syncZoomMeetings(
	client: Client,
	bookingId?: string
): Promise<ZoomSyncResult> {
	const result: ZoomSyncResult = { made: [], failed: [] };
	if (!zoomConfigured()) return result;
	try {
		const { data, error } = await client.rpc('owner_booking_zoom_work', {
			target_booking_id: bookingId,
			max_rows: 20
		});
		if (error) throw error;
		for (const work of data as Work[]) {
			try {
				if (await run(client, work))
					result.made.push({ booking_id: work.booking_id, entry_id: work.entry_id });
			} catch (failure) {
				result.failed.push(work.booking_id);
				// Not connected is a setting, not a fault: the booking already tells its visitor the link will follow.
				if (!(failure instanceof ZoomError && failure.code === 'not_connected'))
					console.error('Could not sync a booking with Zoom.', failure);
			}
		}
	} catch (failure) {
		console.error('Could not read the Zoom work owed to bookings.', failure);
	}
	return result;
}

/** The sweep: a booking that got its meeting late is emailed its link, as when the host adds one. */
export async function sweepZoomMeetings(client: Client, origin: string) {
	const done = await syncZoomMeetings(client);
	for (const { entry_id } of done.made) {
		if (!entry_id) continue;
		try {
			const { data, error } = await client.rpc('owner_booking_for_entry', {
				target_entry_id: entry_id
			});
			if (error) throw error;
			if (data)
				await sendBookingEmail(
					client,
					data as BookingView,
					{ kind: 'video_link', replaced: false },
					origin
				);
		} catch (failure) {
			console.error('Could not queue the email with the new Zoom link.', failure);
		}
	}
	return done;
}
