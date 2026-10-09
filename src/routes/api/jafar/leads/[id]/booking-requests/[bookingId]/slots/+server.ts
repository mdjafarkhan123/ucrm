import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { bookingSlotsQuerySchema } from '$lib/server/validation/booking.schema';

// Jafar business management E2: the open times Jafar can offer when he approves a request at another time -- the
// times the booking page would offer, even while its link is off. A request already answered, or another Lead's,
// has none.

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.bookingId).success) return json([]);
	const parsed = bookingSlotsQuerySchema.safeParse(
		Object.fromEntries(event.url.searchParams.entries())
	);
	if (!parsed.success) return json({ error: 'Ask for a valid range of days.' }, { status: 422 });

	const client = getOwnerSupabaseClient();
	const owned = await client
		.from('platform_bookings')
		.select('id')
		.eq('id', event.params.bookingId)
		.eq('relationship_id', event.params.id)
		.maybeSingle();
	if (owned.error) {
		console.error('Could not read the booking request.', owned.error);
		return json({ error: 'We could not load the open times. Please try again.' }, { status: 500 });
	}
	if (!owned.data) return json([], { headers: PRIVATE_READ_HEADERS });

	const { data, error } = await client.rpc('owner_booking_request_slots', {
		target_booking_id: event.params.bookingId,
		range_from: parsed.data.from,
		range_to: parsed.data.to
	});
	if (error) {
		console.error('Could not read the open times for a request.', error);
		return json({ error: 'We could not load the open times. Please try again.' }, { status: 500 });
	}
	return json(
		(data ?? []).map((slot) => slot.starts_at),
		{ headers: PRIVATE_READ_HEADERS }
	);
};
