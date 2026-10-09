import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { bookingSlotsQuerySchema } from '$lib/server/validation/booking.schema';

// Jafar business management E1: the open times the public booking page shows, for at most 45 days at a time. A
// link that is off or unknown answers with no times, never which.

export const GET: RequestHandler = async (event) => {
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

	const { data, error } = await client.rpc('public_booking_slots', {
		target_slug: event.params.slug,
		range_from: parsed.data.from,
		range_to: parsed.data.to
	});
	if (error) {
		console.error('Could not read the open booking times.', error);
		return json({ error: 'We could not load the open times. Please try again.' }, { status: 500 });
	}
	// Only the starts: every time lasts the meeting's length, and a month of them stays a few kilobytes.
	return json(
		(data ?? []).map((slot) => slot.starts_at),
		{ headers: { 'cache-control': 'private, no-cache' } }
	);
};
