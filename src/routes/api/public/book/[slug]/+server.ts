import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { verifyTurnstileToken } from '$lib/server/security/turnstile';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import { sendBookingEmail } from '$lib/server/jafar/booking-emails';
import { bookingToken, bookingTokenHash } from '$lib/server/jafar/booking-links';
import { askHostForVideoLink, hostTimeWords } from '$lib/server/jafar/booking-video';
import { publicBookingSchema } from '$lib/server/validation/booking.schema';
import { LOCATION_WORDS, type BookedCall, type BookingView } from '$lib/jafar/booking';

// Jafar business management E1: a visitor books a call. The database takes the host's lock and checks the time is
// still open, so of two visitors racing for one time only the first gets it; the second is told to pick another.
// E2: a meeting type in approval mode records a request instead, holding no time. The visitor's link to change or
// cancel is stored (as its hash) before any email carries it. The email and Jafar's alert follow the booking and
// never undo it.

type BookResult =
	| ({ outcome: 'booked' | 'requested' } & BookingView)
	| { outcome: 'taken' }
	| { outcome: 'unavailable' };

const TAKEN =
	'Someone has just booked that time. Please choose another — the list now shows what is still open.';

export const POST: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Please check the highlighted fields.' }, { status: 400 });
	}
	const parsed = publicBookingSchema.safeParse(body);
	if (!parsed.success) {
		const fieldErrors: Record<string, string> = {};
		for (const issue of parsed.error.issues)
			fieldErrors[issue.path.join('.') || 'form'] ??= issue.message;
		return json(
			{ error: 'Please check the highlighted fields.', field_errors: fieldErrors },
			{ status: 422 }
		);
	}
	const data = parsed.data;
	const client = getOwnerSupabaseClient();
	const clientAddress = event.getClientAddress();

	const rateLimit = await checkRateLimit(client, {
		bucketKey: `public-booking:${clientAddress}`,
		windowSeconds: 900,
		maxAttempts: 8
	});
	if (!rateLimit.allowed) return rateLimitedResponse(rateLimit.retryAfterSeconds);

	if (!(await verifyTurnstileToken(data.turnstile_token, clientAddress)))
		return json({ error: "We couldn't verify you're human. Please try again." }, { status: 422 });

	const { data: rpcData, error } = await client.rpc('public_booking_book', {
		target_slug: event.params.slug,
		target_starts_at: data.starts_at,
		target_name: data.name,
		target_email: data.email,
		target_phone: data.phone,
		target_time_zone: data.time_zone,
		target_business_name: data.business_name,
		target_country_code: data.country_code,
		target_trade: data.trade,
		target_note: data.note ?? undefined
	});
	if (error) {
		console.error('Could not save a booking.', error);
		return json(
			{ error: 'We could not book that time. Please try again shortly.' },
			{ status: 500 }
		);
	}
	const result = rpcData as BookResult;
	if (result.outcome === 'unavailable')
		return json({ error: 'This booking page is not taking bookings right now.' }, { status: 404 });
	if (result.outcome === 'taken') return json({ error: TAKEN, taken: true }, { status: 409 });

	const requested = result.outcome === 'requested';
	const call: BookedCall = {
		starts_at: result.starts_at,
		ends_at: result.ends_at,
		name: result.name,
		duration_minutes: result.duration_minutes,
		location_kind: result.location_kind,
		video_join_url: result.video_join_url,
		host_name: result.host_name
	};

	try {
		const { error: linkError } = await client
			.from('platform_bookings')
			.update({ manage_token_hash: bookingTokenHash(bookingToken(result.booking_id)) })
			.eq('id', result.booking_id);
		if (linkError) throw linkError;
		await sendBookingEmail(
			client,
			result,
			{ kind: requested ? 'requested' : 'booked' },
			event.url.origin
		);
	} catch (emailError) {
		console.error('Could not queue the booking email.', emailError);
	}

	try {
		const when = await hostTimeWords(client, call.starts_at);
		await raiseOwnerAlert(client, {
			kind: requested ? 'sales_call_requested' : 'sales_call_booked',
			severity: requested ? 'attention' : 'info',
			title: requested
				? `${data.business_name} asked for a ${call.name}`
				: `${data.business_name} booked a ${call.name}`,
			body: requested
				? `${data.name} asked for ${when}. The time is not held until you approve it on their Lead.`
				: call.location_kind === 'phone'
					? `${data.name} booked ${when}. Call them on ${data.phone}.`
					: `${data.name} booked ${when} as a ${LOCATION_WORDS[call.location_kind]}.`,
			target: { targetKind: 'business_relationship', targetId: result.relationship_id },
			origin: event.url.origin
		});
		if (!requested) await askHostForVideoLink(client, result);
	} catch (alertError) {
		console.error('Could not record the new-booking alert.', alertError);
	}

	return json({ ok: true, requested, call });
};
