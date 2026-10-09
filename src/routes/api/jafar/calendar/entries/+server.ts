import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { Json } from '$lib/database.types';
import { databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	CALLS_REFUSED,
	adoptTimeZone,
	calendarViewer,
	isPlainRefusal,
	parseBody
} from '$lib/server/jafar/calendar';
import { calendarEntryCreateSchema } from '$lib/server/validation/calendar.schema';

// Jafar business management C2: books a call with a business (it becomes the business's next action) or blocks out
// Busy time. D3b: a teammate books calls only with Leads & Deals open to change; Busy blocks are their own.

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const parsed = await parseBody(event, calendarEntryCreateSchema);
	if (!parsed.ok) return parsed.response;
	const input = parsed.data;
	const viewer = calendarViewer(session);
	if (input.kind === 'call' && !viewer.canWorkCalls)
		return json({ error: CALLS_REFUSED }, { status: 403 });
	const client = getOwnerSupabaseClient();

	try {
		await adoptTimeZone(client, input.time_zone, viewer.memberId);
		const { data, error } =
			input.kind === 'call'
				? await client.rpc('owner_calendar_book_call', {
						actor_email: session.email,
						target_relationship_id: input.relationship_id,
						target_starts_at: input.starts_at,
						target_ends_at: input.ends_at,
						target_title: input.title ?? undefined,
						target_notes: input.notes ?? undefined,
						target_reminders: (input.reminders as Json | null) ?? undefined
					})
				: await client.rpc('owner_calendar_save_busy', {
						actor_email: session.email,
						// The command has no default here: null is what makes a new Busy block.
						target_id: null as unknown as string,
						target_starts_at: input.starts_at,
						target_ends_at: input.ends_at,
						target_title: input.title ?? undefined,
						viewer_member_id: viewer.memberId
					});
		if (isPlainRefusal(error)) return validationError({ form: error.message }, 409);
		if (error) throw error;
		if (!data) return notFound('That business could not be found.');
		return json({ id: data }, { status: 201 });
	} catch (error) {
		console.error('Could not save the calendar entry.', error);
		return databaseError();
	}
};
