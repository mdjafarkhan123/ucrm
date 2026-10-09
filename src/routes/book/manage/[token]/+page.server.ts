import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { verifiedTokenHash } from '$lib/server/jafar/booking-links';
import { managedBooking } from '$lib/server/jafar/booking-manage';
import type { BookingView } from '$lib/jafar/booking';
import type { PageServerLoad } from './$types';

// Jafar business management E2: the visitor's own page for one booking, reached from the link in its emails. It
// arrives with the booking and, while it can still change, its first 45 days of open times, so moving needs no
// second wait. A guessed or altered link shows as not valid.

const FIRST_WINDOW_DAYS = 45;

export const load: PageServerLoad = async ({ params, setHeaders }) => {
	// The page shows someone's booking: never cache it, never let it be indexed or leak through a referrer.
	setHeaders({ 'cache-control': 'private, no-store', 'referrer-policy': 'no-referrer' });
	const hash = verifiedTokenHash(params.token);
	if (!hash) return { booking: null, firstWindow: { to: '', starts: [] } };

	const client = getOwnerSupabaseClient();
	const from = new Date();
	const to = new Date(from.getTime() + FIRST_WINDOW_DAYS * 24 * 60 * 60 * 1000);
	const [bookingResult, slotsResult] = await Promise.all([
		client.rpc('public_booking_manage', { target_token_hash: hash }),
		client.rpc('public_booking_manage_slots', {
			target_token_hash: hash,
			range_from: from.toISOString(),
			range_to: to.toISOString()
		})
	]);
	if (bookingResult.error) throw bookingResult.error;
	if (slotsResult.error) throw slotsResult.error;

	const view = bookingResult.data as BookingView | null;
	return {
		booking: view ? managedBooking(view) : null,
		firstWindow: {
			to: to.toISOString(),
			starts: (slotsResult.data ?? []).map((slot) => slot.starts_at)
		}
	};
};
