import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { verifyTurnstileToken } from '$lib/server/security/turnstile';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import { sendBookingConfirmation } from '$lib/server/jafar/booking-confirmation';
import { publicBookingSchema } from '$lib/server/validation/booking.schema';
import { dateWords, timeWords, type BookedCall } from '$lib/jafar/booking';

// Jafar business management E1: a visitor books a call. The database takes the host's lock and checks the time is
// still open, so of two visitors racing for one time only the first gets it; the second is told to pick another.
// The confirmation email and Jafar's alert follow the booking and never undo it.

type BookResult =
	| ({
			outcome: 'booked';
			booking_id: string;
			entry_id: string;
			relationship_id: string;
	  } & BookedCall)
	| { outcome: 'taken' | 'unavailable' };

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
	if (result.outcome !== 'booked') return json({ error: TAKEN, taken: true }, { status: 409 });

	const call: BookedCall = {
		starts_at: result.starts_at,
		ends_at: result.ends_at,
		name: result.name,
		duration_minutes: result.duration_minutes,
		location_kind: result.location_kind,
		host_name: result.host_name
	};

	try {
		await sendBookingConfirmation(client, {
			bookingId: result.booking_id,
			call,
			visitorName: data.name,
			visitorEmail: data.email,
			visitorPhone: data.phone,
			timeZone: data.time_zone
		});
	} catch (emailError) {
		console.error('Could not queue the booking confirmation email.', emailError);
	}

	try {
		// The time in the host's own zone, as their calendar shows it.
		const prefs = await client.rpc('owner_calendar_preferences', {});
		const hostZone = (prefs.data as { time_zone: string | null } | null)?.time_zone ?? 'UTC';
		await raiseOwnerAlert(client, {
			kind: 'sales_call_booked',
			severity: 'info',
			title: `${data.business_name} booked a ${call.name}`,
			body: `${data.name} booked ${dateWords(call.starts_at, hostZone, 'en-GB')} at ${timeWords(call.starts_at, hostZone, 'en-GB')}. Call them on ${data.phone}.`,
			target: { targetKind: 'business_relationship', targetId: result.relationship_id },
			origin: event.url.origin
		});
	} catch (alertError) {
		console.error('Could not record the new-booking alert.', alertError);
	}

	return json({ ok: true, call });
};
