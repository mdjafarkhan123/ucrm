import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { calendarWindowQuerySchema } from '$lib/server/validation/calendar.schema';

// Jafar business management C2: everything on the Business Management calendar for one view -- a day, a week or a
// six-week month -- in one database call. D3b: each person sees only their own calls, follow-ups and Busy blocks.

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const parsed = calendarWindowQuerySchema.safeParse(Object.fromEntries(event.url.searchParams));
	if (!parsed.success) return validationError({ form: 'The calendar view is invalid.' });

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_calendar_window', {
		from_date: parsed.data.from,
		to_date: parsed.data.to,
		zone: parsed.data.zone,
		viewer_member_id: session.memberId ?? undefined
	});
	if (error) {
		if (error.code === '22023') return validationError({ form: error.message });
		console.error('Could not load the calendar.', error);
		return json({ error: 'The calendar could not be loaded.' }, { status: 500 });
	}
	return json(data, { headers: PRIVATE_READ_HEADERS });
};
