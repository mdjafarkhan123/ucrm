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
import { isPlainRefusal, parseBody } from '$lib/server/jafar/calendar';
import { calendarEntryChangeSchema } from '$lib/server/validation/calendar.schema';

// Jafar business management C2: one call or Busy block -- read it, move it, edit its words and reminders, close a
// call with its outcome, or remove a Busy block. Calls are never deleted: a cancelled one stays in the history.

const NOT_FOUND = 'This is no longer on the calendar.';

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(NOT_FOUND);
	const { data, error } = await getOwnerSupabaseClient().rpc('owner_calendar_entry', {
		target_id: event.params.id
	});
	if (error) {
		console.error('Could not load the calendar entry.', error);
		return json({ error: 'This could not be loaded.' }, { status: 500 });
	}
	if (!data) return notFound(NOT_FOUND);
	return json(data, { headers: PRIVATE_READ_HEADERS });
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

	try {
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
								target_title: change.title ?? undefined
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
		return json({ ok: true });
	} catch (error) {
		console.error('Could not change the calendar entry.', error);
		return databaseError();
	}
};

export const DELETE: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(NOT_FOUND);
	const { data, error } = await getOwnerSupabaseClient().rpc('owner_calendar_delete_busy', {
		target_id: event.params.id
	});
	if (error) {
		console.error('Could not remove the Busy block.', error);
		return databaseError();
	}
	if (!data) return notFound(NOT_FOUND);
	return json({ ok: true });
};
