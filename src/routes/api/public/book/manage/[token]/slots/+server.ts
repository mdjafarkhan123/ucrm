import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { verifiedTokenHash } from '$lib/server/jafar/booking-links';
import { bookingSlotsQuerySchema } from '$lib/server/validation/booking.schema';

// Jafar business management E2: the times a visitor could move their booking to -- the booking page's rules, with
// their own call not counted as taken. None once the change deadline has passed.

export const GET: RequestHandler = async (event) => {
	const hash = verifiedTokenHash(event.params.token);
	if (!hash) return json([], { headers: { 'cache-control': 'private, no-cache' } });

	const client = getOwnerSupabaseClient();
	const rateLimit = await checkRateLimit(client, {
		bucketKey: `public-booking-slots:${event.getClientAddress()}`,
		windowSeconds: 60,
		maxAttempts: 60
	});
	if (!rateLimit.allowed) return rateLimitedResponse(rateLimit.retryAfterSeconds);

	const parsed = bookingSlotsQuerySchema.safeParse(
		Object.fromEntries(event.url.searchParams.entries())
	);
	if (!parsed.success) return json({ error: 'Ask for a valid range of days.' }, { status: 422 });

	const { data, error } = await client.rpc('public_booking_manage_slots', {
		target_token_hash: hash,
		range_from: parsed.data.from,
		range_to: parsed.data.to
	});
	if (error) {
		console.error('Could not read the open times for a booking change.', error);
		return json({ error: 'We could not load the open times. Please try again.' }, { status: 500 });
	}
	return json(
		(data ?? []).map((slot) => slot.starts_at),
		{ headers: { 'cache-control': 'private, no-cache' } }
	);
};
