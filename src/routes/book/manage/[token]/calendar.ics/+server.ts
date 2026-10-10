import { error } from '@sveltejs/kit';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { bookingIcs } from '$lib/server/jafar/booking-calendar';
import { bookingManageUrl, verifiedTokenHash } from '$lib/server/jafar/booking-links';
import type { BookingView } from '$lib/jafar/booking';
import type { RequestHandler } from './$types';

// Jafar business management E2b: the visitor's booked call as a calendar file, from the "Add to calendar" link in its
// emails. The booking link is the only key, as on the booking's own page; a request that holds no time has no file.

export const GET: RequestHandler = async ({ params, url }) => {
	const hash = verifiedTokenHash(params.token);
	if (!hash) error(404, 'This link is not valid.');

	const { data, error: readError } = await getOwnerSupabaseClient().rpc('public_booking_manage', {
		target_token_hash: hash
	});
	if (readError) throw readError;
	const booking = data as BookingView | null;
	if (!booking || booking.status === 'requested' || !booking.entry_id)
		error(404, 'This call is not booked.');

	return new Response(bookingIcs(booking, bookingManageUrl(url.origin, booking.booking_id)), {
		headers: {
			'content-type': 'text/calendar; charset=utf-8',
			'content-disposition': 'attachment; filename="uplift-call.ics"',
			'cache-control': 'private, no-store',
			'referrer-policy': 'no-referrer'
		}
	});
};
