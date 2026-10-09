import { env as publicEnv } from '$env/dynamic/public';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import type { PublicMeetingType } from '$lib/jafar/booking';
import type { PageServerLoad } from './$types';

// Jafar business management E1: the public booking page. The page arrives with its first 45 days of open times,
// so a visitor sees available days at once instead of waiting for a second request; later months load as they
// are opened. Times are instants -- the browser shows them in the visitor's own zone.

const FIRST_WINDOW_DAYS = 45;

export const load: PageServerLoad = async ({ params, setHeaders }) => {
	const client = getOwnerSupabaseClient();
	const from = new Date();
	const to = new Date(from.getTime() + FIRST_WINDOW_DAYS * 24 * 60 * 60 * 1000);

	const [meetingResult, slotsResult, approvalResult] = await Promise.all([
		client.rpc('public_booking_page', { target_slug: params.slug }),
		client.rpc('public_booking_slots', {
			target_slug: params.slug,
			range_from: from.toISOString(),
			range_to: to.toISOString()
		}),
		// E2: in approval mode the page sends a request rather than a booking.
		client
			.from('platform_meeting_types')
			.select('requires_approval')
			.eq('slug', params.slug)
			.maybeSingle()
	]);
	if (meetingResult.error) throw meetingResult.error;
	if (approvalResult.error) throw approvalResult.error;
	if (slotsResult.error) throw slotsResult.error;

	// Open times change with every booking; never let a cache keep a taken one.
	setHeaders({ 'cache-control': 'private, no-store' });
	return {
		meeting: (meetingResult.data as PublicMeetingType | null) ?? null,
		firstWindow: {
			from: from.toISOString(),
			to: to.toISOString(),
			starts: (slotsResult.data ?? []).map((slot) => slot.starts_at)
		},
		requiresApproval: approvalResult.data?.requires_approval ?? false,
		turnstileSiteKey: publicEnv.PUBLIC_TURNSTILE_SITE_KEY ?? ''
	};
};
