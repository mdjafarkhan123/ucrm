import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { Json } from '$lib/database.types';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { isPlainRefusal, parseBody } from '$lib/server/jafar/calendar';
import { calendarPreferencesSchema } from '$lib/server/validation/calendar.schema';

// Jafar business management C2: My preferences -- the time zone and default reminders. Saving rewrites every
// reminder still to come that follows them.

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const { data, error } = await getOwnerSupabaseClient().rpc('owner_calendar_preferences');
	if (error) {
		console.error('Could not load the calendar preferences.', error);
		return json({ error: 'Your calendar choices could not be loaded.' }, { status: 500 });
	}
	return json(data, { headers: PRIVATE_READ_HEADERS });
};

export const PATCH: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const parsed = await parseBody(event, calendarPreferencesSchema);
	if (!parsed.ok) return parsed.response;
	const { data, error } = await getOwnerSupabaseClient().rpc('owner_calendar_save_preferences', {
		target_time_zone: parsed.data.time_zone,
		target_reminder_defaults: parsed.data.reminder_defaults as Json | undefined
	});
	if (isPlainRefusal(error)) return validationError({ form: error.message }, 409);
	if (error) {
		console.error('Could not save the calendar preferences.', error);
		return databaseError();
	}
	return json(data);
};
