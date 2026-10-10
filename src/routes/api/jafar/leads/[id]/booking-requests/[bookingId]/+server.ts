import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { isPlainRefusal, parseBody } from '$lib/server/jafar/calendar';
import { sendBookingEmail } from '$lib/server/jafar/booking-emails';
import { askHostForVideoLink, withZoomMeeting } from '$lib/server/jafar/booking-video';
import { bookingDecisionSchema } from '$lib/server/validation/booking.schema';
import type { BookingView } from '$lib/jafar/booking';

// Jafar business management E2: approve a booking request -- at the time asked for, or another open one -- or
// decline it. The time is checked again now (a request never held it), so a time taken since asks for another. The
// visitor's email follows the answer and never undoes it.

type Decision =
	| ({ outcome: 'approved'; requested_starts_at: string } & BookingView)
	| ({ outcome: 'declined' } & BookingView)
	| { outcome: 'taken' }
	| { outcome: 'closed' }
	| { outcome: 'unknown' };

const GONE = 'This request has already been answered or withdrawn.';

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (
		!z.uuid().safeParse(event.params.id).success ||
		!z.uuid().safeParse(event.params.bookingId).success
	)
		return notFound(GONE);
	const parsed = await parseBody(event, bookingDecisionSchema);
	if (!parsed.ok) return parsed.response;
	const answer = parsed.data;
	const client = getOwnerSupabaseClient();

	// Only a request of the Lead in the address: another Lead's reads as not there.
	const open = await client.rpc('owner_booking_requests', {
		target_relationship_id: event.params.id
	});
	if (open.error) {
		console.error('Could not load the booking requests.', open.error);
		return databaseError();
	}
	if (!(open.data as BookingView[]).some((item) => item.booking_id === event.params.bookingId))
		return notFound(GONE);

	const { data, error } = await client.rpc('owner_booking_decide', {
		actor_email: session.email,
		target_booking_id: event.params.bookingId,
		decision: answer.decision,
		target_starts_at: (answer.decision === 'approve' && answer.starts_at) || undefined
	});
	if (isPlainRefusal(error)) return validationError({ form: error.message }, 409);
	if (error) {
		console.error('Could not answer the booking request.', error);
		return databaseError();
	}
	let result = data as Decision;
	if (result.outcome === 'unknown' || result.outcome === 'closed') return notFound(GONE);
	if (result.outcome === 'taken')
		return validationError(
			{ starts_at: 'That time is no longer free. Choose another time to offer.' },
			409
		);

	// E4b: an approved Zoom call gets its meeting before the visitor is told.
	if (result.outcome === 'approved')
		result = { ...result, ...(await withZoomMeeting(client, result)) } as typeof result;

	try {
		await sendBookingEmail(
			client,
			result,
			result.outcome === 'approved'
				? { kind: 'approved', requestedStartsAt: result.requested_starts_at }
				: { kind: 'declined' },
			event.url.origin
		);
	} catch (emailError) {
		console.error('Could not queue the booking answer email.', emailError);
	}
	if (result.outcome === 'approved')
		try {
			await askHostForVideoLink(client, result);
		} catch (alertError) {
			console.error('Could not ask the host for the video link.', alertError);
		}
	return json({ ok: true, outcome: result.outcome });
};
