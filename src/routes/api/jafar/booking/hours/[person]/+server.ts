import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { adoptTimeZone, isPlainRefusal, parseBody } from '$lib/server/jafar/calendar';
import { bookingHoursBodySchema } from '$lib/server/validation/booking.schema';

// Jafar business management E3: one host's weekly hours -- "jafar" or a teammate's id -- in that person's own time
// zone (their My preferences). Only Jafar reaches Booking settings.

export const PATCH: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const person = event.params.person;
	if (person !== 'jafar' && !z.uuid().safeParse(person).success)
		return notFound('That person is no longer on the team.');
	const memberId = person === 'jafar' ? null : person;
	const parsed = await parseBody(event, bookingHoursBodySchema);
	if (!parsed.ok) return parsed.response;
	const client = getOwnerSupabaseClient();
	try {
		// Jafar's first save gives him the browser's zone when he has none; a teammate's zone is their own choice.
		if (memberId === null) await adoptTimeZone(client, parsed.data.time_zone, undefined);
		const { data, error } = await client.rpc('owner_booking_save_hours', {
			target_member_id: memberId as string,
			target_hours: parsed.data.hours
		});
		if (isPlainRefusal(error)) return validationError({ form: error.message }, 409);
		if (error) throw error;
		return json(data);
	} catch (error) {
		console.error('Could not save the weekly hours.', error);
		return databaseError();
	}
};
