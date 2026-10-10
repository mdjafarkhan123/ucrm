import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import type { Json } from '$lib/database.types';
import {
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	validationError
} from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import type { OwnerSession } from '$lib/server/auth/owner';
import {
	CALLS_REFUSED,
	calendarViewer,
	isPlainRefusal,
	parseBody
} from '$lib/server/jafar/calendar';
import { calendarEntryChangeSchema } from '$lib/server/validation/calendar.schema';
import { sendBookingEmail } from '$lib/server/jafar/booking-emails';
import { withZoomMeeting } from '$lib/server/jafar/booking-video';
import type { BookingView } from '$lib/jafar/booking';

// Jafar business management C2: one call or Busy block -- read it, move it, edit its words and reminders, close a
// call with its outcome, or remove a Busy block. Calls are never deleted: a cancelled one stays in the history.
// E2: moving or cancelling a call a visitor booked online emails them, as their own change would.

const NOT_FOUND = 'This is no longer on the calendar.';

type Entry = { kind: 'call' | 'busy'; owner_member_id: string | null };

type Client = ReturnType<typeof getOwnerSupabaseClient>;

/** The visitor's booking behind a call, or null for a call staff booked themselves. */
async function bookingFor(client: Client, entryId: string) {
	const { data, error } = await client.rpc('owner_booking_for_entry', { target_entry_id: entryId });
	if (error) throw error;
	return (data as BookingView | null) ?? null;
}

/**
 * D3b: the entry when this person may see it -- their own, or a call of a Lead they can open. Someone else's Busy
 * block is private, so it reads as not there.
 */
async function visibleEntry(session: OwnerSession, id: string) {
	const { data, error } = await getOwnerSupabaseClient().rpc('owner_calendar_entry', {
		target_id: id
	});
	if (error) throw error;
	const entry = data as Entry | null;
	if (!entry) return null;
	const own = entry.owner_member_id === session.memberId;
	return own || (entry.kind === 'call' && calendarViewer(session).canSeeCalls) ? entry : null;
}

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(NOT_FOUND);
	try {
		const entry = await visibleEntry(session, event.params.id);
		if (!entry) return notFound(NOT_FOUND);
		return json(entry, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not load the calendar entry.', error);
		return json({ error: 'This could not be loaded.' }, { status: 500 });
	}
};

export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(NOT_FOUND);
	const parsed = await parseBody(event, calendarEntryChangeSchema);
	if (!parsed.ok) return parsed.response;
	const change = parsed.data;
	const client = getOwnerSupabaseClient();
	const target_id = event.params.id;
	const viewer = calendarViewer(session);

	try {
		const entry = await visibleEntry(session, target_id);
		if (!entry) return notFound(NOT_FOUND);
		if (entry.kind === 'call' && !viewer.canWorkCalls)
			return json({ error: CALLS_REFUSED }, { status: 403 });
		const tellsVisitor =
			entry.kind === 'call' &&
			(change.action === 'move' || (change.action === 'close' && change.outcome === 'cancelled'));
		const before = tellsVisitor ? await bookingFor(client, target_id) : null;
		const { data, error } =
			change.action === 'move'
				? await client.rpc('owner_calendar_move', {
						actor_email: session.email,
						target_id,
						target_starts_at: change.starts_at,
						target_ends_at: change.ends_at
					})
				: change.action === 'edit'
					? await client.rpc('owner_calendar_edit', {
							target_id,
							target_title: change.title ?? '',
							target_notes: change.notes ?? '',
							target_reminders: change.reminders as Json
						})
					: change.action === 'busy'
						? await client.rpc('owner_calendar_save_busy', {
								actor_email: session.email,
								target_id,
								target_starts_at: change.starts_at,
								target_ends_at: change.ends_at,
								target_title: change.title ?? undefined,
								viewer_member_id: viewer.memberId
							})
						: await client.rpc('owner_calendar_close_call', {
								actor_email: session.email,
								target_id,
								outcome: change.outcome,
								target_next_action: change.next_action?.text,
								target_due_on: change.next_action?.due_on,
								target_due_at: change.next_action?.due_at ?? undefined
							});
		if (isPlainRefusal(error)) return validationError({ form: error.message }, 409);
		if (error) throw error;
		if (!data) return notFound(NOT_FOUND);
		if (before) await tellVisitor(client, target_id, before, event.url.origin);
		return json({ ok: true });
	} catch (error) {
		console.error('Could not change the calendar entry.', error);
		return databaseError();
	}
};

/** Emails the visitor about a staff change; the change stands even when the email cannot be queued. */
async function tellVisitor(client: Client, entryId: string, before: BookingView, origin: string) {
	try {
		const current = await bookingFor(client, entryId);
		if (!current) return;
		const after = await withZoomMeeting(client, current);
		if (after.call_status === 'cancelled')
			await sendBookingEmail(client, after, { kind: 'cancelled', by: 'staff' }, origin);
		else if (after.starts_at !== before.starts_at)
			await sendBookingEmail(
				client,
				after,
				{ kind: 'moved', fromStartsAt: before.starts_at, by: 'staff' },
				origin
			);
	} catch (error) {
		console.error('Could not queue the email telling the visitor about the change.', error);
	}
}

export const DELETE: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(NOT_FOUND);
	const { data, error } = await getOwnerSupabaseClient().rpc('owner_calendar_delete_busy', {
		target_id: event.params.id,
		viewer_member_id: session.memberId ?? undefined
	});
	if (error) {
		console.error('Could not remove the Busy block.', error);
		return databaseError();
	}
	if (!data) return notFound(NOT_FOUND);
	return json({ ok: true });
};
