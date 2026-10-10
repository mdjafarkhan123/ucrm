import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import { sendBookingEmail } from '$lib/server/jafar/booking-emails';
import { verifiedTokenHash } from '$lib/server/jafar/booking-links';
import { withZoomMeeting } from '$lib/server/jafar/booking-video';
import { managedBooking } from '$lib/server/jafar/booking-manage';
import { bookingChangeSchema } from '$lib/server/validation/booking.schema';
import { dateWords, timeWords, type BookingView } from '$lib/jafar/booking';

// Jafar business management E2: the visitor's link -- move the booking to another open time, or cancel it. The link
// is the visitor's only key, so a guessed or altered one reads as unknown. The database takes the host's lock and
// checks Jafar's deadline and the new time again; the emails and Jafar's alert follow and never undo the change.

type ChangeResult =
	| ({ outcome: 'moved'; from_starts_at: string } & BookingView)
	| ({ outcome: 'cancelled' } & BookingView)
	| { outcome: 'taken' }
	| { outcome: 'closed' }
	| { outcome: 'unknown' };

const UNKNOWN = 'This link is not valid. Please use the link in your latest email from us.';
const CLOSED =
	'This booking can no longer be changed online. Reply to your confirmation email and we will help.';
const TAKEN =
	'Someone has just booked that time. Please choose another — the list now shows what is still open.';

export const POST: RequestHandler = async (event) => {
	const hash = verifiedTokenHash(event.params.token);
	if (!hash) return json({ error: UNKNOWN }, { status: 404 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Please try again.' }, { status: 400 });
	}
	const parsed = bookingChangeSchema.safeParse(body);
	if (!parsed.success) {
		const fieldErrors: Record<string, string> = {};
		for (const issue of parsed.error.issues)
			fieldErrors[issue.path.join('.') || 'form'] ??= issue.message;
		return json(
			{ error: 'Please check the highlighted fields.', field_errors: fieldErrors },
			{ status: 422 }
		);
	}
	const change = parsed.data;
	const client = getOwnerSupabaseClient();

	const rateLimit = await checkRateLimit(client, {
		bucketKey: `public-booking-change:${event.getClientAddress()}`,
		windowSeconds: 900,
		maxAttempts: 20
	});
	if (!rateLimit.allowed) return rateLimitedResponse(rateLimit.retryAfterSeconds);

	const { data, error } =
		change.action === 'move'
			? await client.rpc('public_booking_reschedule', {
					target_token_hash: hash,
					target_starts_at: change.starts_at
				})
			: await client.rpc('public_booking_cancel', {
					target_token_hash: hash,
					target_reason: change.reason ?? undefined
				});
	if (error) {
		console.error('Could not change a booking.', error);
		return json(
			{ error: 'We could not change your booking. Please try again shortly.' },
			{ status: 500 }
		);
	}
	const changed = data as ChangeResult;
	if (changed.outcome === 'unknown') return json({ error: UNKNOWN }, { status: 404 });
	if (changed.outcome === 'closed') return json({ error: CLOSED, closed: true }, { status: 409 });
	if (changed.outcome === 'taken') return json({ error: TAKEN, taken: true }, { status: 409 });

	// E4b: the Zoom meeting follows the booking (moved, or deleted with a cancelled call) before the visitor reads on.
	const result = { ...changed, ...(await withZoomMeeting(client, changed)) } as typeof changed;

	const moved = result.outcome === 'moved';
	const unchanged = moved && result.from_starts_at === result.starts_at;
	if (!unchanged) {
		try {
			await sendBookingEmail(
				client,
				result,
				moved
					? { kind: 'moved', fromStartsAt: result.from_starts_at, by: 'visitor' }
					: { kind: 'cancelled', by: 'visitor' },
				event.url.origin
			);
		} catch (emailError) {
			console.error('Could not queue the booking change email.', emailError);
		}

		try {
			const prefs = await client.rpc('owner_calendar_preferences', {});
			const hostZone = (prefs.data as { time_zone: string | null } | null)?.time_zone ?? 'UTC';
			const at = (instant: string) =>
				`${dateWords(instant, hostZone, 'en-GB')} at ${timeWords(instant, hostZone, 'en-GB')}`;
			const request = result.status !== 'booked' ? 'request for a ' : '';
			await raiseOwnerAlert(client, {
				kind: moved ? 'sales_call_moved' : 'sales_call_cancelled',
				severity: moved ? 'info' : 'attention',
				title: moved
					? `${result.business_name} moved their ${request}${result.name}`
					: `${result.business_name} cancelled their ${request}${result.name}`,
				body: moved
					? `${result.visitor_name} moved it from ${at(result.from_starts_at)} to ${at(result.starts_at)}.`
					: `${result.visitor_name} cancelled ${at(result.starts_at)}.${change.action === 'cancel' && change.reason ? ` They said: "${change.reason}"` : ''}`,
				target: { targetKind: 'business_relationship', targetId: result.relationship_id },
				origin: event.url.origin
			});
		} catch (alertError) {
			console.error('Could not record the booking change alert.', alertError);
		}
	}

	return json({ ok: true, booking: managedBooking(result) });
};
