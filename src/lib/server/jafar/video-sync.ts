import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { sendBookingEmail } from '$lib/server/jafar/booking-emails';
import {
	GoogleError,
	createMeetEvent,
	deleteMeetEvent,
	googleConfigured,
	moveMeetEvent
} from '$lib/server/jafar/google';
import {
	ZoomError,
	createZoomMeeting,
	deleteZoomMeeting,
	moveZoomMeeting,
	zoomConfigured
} from '$lib/server/jafar/zoom';
import type { BookingView, LocationKind } from '$lib/jafar/booking';

// Jafar business management E4b, E5: keeps each booking's Zoom meeting or Google Meet event in step with the booking.
// The database says what is owed (owner_booking_video_work: make, move or delete); this does it. A booking change runs it for that booking
// straight away, and the worker's sweep runs it for every booking, so a Zoom outage only delays a meeting -- the
// visitor is told the details will follow until it exists (E4a), and the sweep sends the link when it does.

type Client = SupabaseClient<Database>;

type Meeting = { topic: string; startsAt: string; endsAt: string };

/** What each provider can do for a booking; a booking only ever uses the provider it was booked with. */
type Provider = {
	name: string;
	configured: () => boolean;
	create: (client: Client, input: Meeting) => Promise<{ meetingId: string; joinUrl: string }>;
	move: (client: Client, meetingId: string, input: Meeting) => Promise<void>;
	remove: (client: Client, meetingId: string) => Promise<void>;
	/** Not connected is a setting, not a fault: the booking already tells its visitor the link will follow. */
	isNotConnected: (failure: unknown) => boolean;
};

const PROVIDERS: Partial<Record<LocationKind, Provider>> = {
	zoom: {
		name: 'Zoom',
		configured: zoomConfigured,
		create: createZoomMeeting,
		move: moveZoomMeeting,
		remove: deleteZoomMeeting,
		isNotConnected: (failure) => failure instanceof ZoomError && failure.code === 'not_connected'
	},
	google_meet: {
		name: 'Google Meet',
		configured: googleConfigured,
		create: createMeetEvent,
		move: moveMeetEvent,
		remove: deleteMeetEvent,
		isNotConnected: (failure) => failure instanceof GoogleError && failure.code === 'not_connected'
	}
};

/** Deletes a provider meeting UCRM made; for a link the host replaced it with their own. */
export async function deleteProviderMeeting(client: Client, kind: LocationKind, meetingId: string) {
	await PROVIDERS[kind]?.remove(client, meetingId);
}

type Work = {
	booking_id: string;
	entry_id: string | null;
	action: 'create' | 'update' | 'delete';
	meeting_id: string | null;
	starts_at: string | null;
	ends_at: string | null;
	topic: string;
};

export type VideoSyncResult = {
	made: { booking_id: string; entry_id: string | null }[];
	failed: string[];
};

async function made(client: Client, provider: Provider, work: Work) {
	if (!work.starts_at || !work.ends_at) return false;
	const meeting = await provider.create(client, {
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
		await provider
			.remove(client, meeting.meetingId)
			.catch((cleanup) =>
				console.error(`Could not remove a ${provider.name} meeting that was not used.`, cleanup)
			);
		if (error) throw error;
		return false;
	}
	return true;
}

async function run(client: Client, provider: Provider, work: Work) {
	if (work.action === 'create') return made(client, provider, work);
	if (!work.meeting_id) return false;
	if (work.action === 'update') {
		if (!work.starts_at || !work.ends_at) return false;
		await provider.move(client, work.meeting_id, {
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
	await provider.remove(client, work.meeting_id);
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
 * Does the video work owed to one booking, or to every booking when none is named. Never throws: a failure is logged
 * and left for the next sweep. `made` lists the bookings that just got a meeting.
 */
export async function syncVideoMeetings(
	client: Client,
	bookingId?: string
): Promise<VideoSyncResult> {
	const result: VideoSyncResult = { made: [], failed: [] };
	for (const [kind, provider] of Object.entries(PROVIDERS) as [LocationKind, Provider][]) {
		if (!provider.configured()) continue;
		try {
			const { data, error } = await client.rpc('owner_booking_video_work', {
				target_provider: kind,
				target_booking_id: bookingId,
				max_rows: 20
			});
			if (error) throw error;
			for (const work of data as Work[]) {
				try {
					if (await run(client, provider, work))
						result.made.push({ booking_id: work.booking_id, entry_id: work.entry_id });
				} catch (failure) {
					result.failed.push(work.booking_id);
					if (!provider.isNotConnected(failure))
						console.error(`Could not sync a booking with ${provider.name}.`, failure);
				}
			}
		} catch (failure) {
			console.error(`Could not read the ${provider.name} work owed to bookings.`, failure);
		}
	}
	return result;
}

/** The sweep: a booking that got its meeting late is emailed its link, as when the host adds one. */
export async function sweepVideoMeetings(client: Client, origin: string) {
	const done = await syncVideoMeetings(client);
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
			console.error('Could not queue the email with the new video link.', failure);
		}
	}
	return done;
}
