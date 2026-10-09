import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { parseBody } from '$lib/server/jafar/calendar';
import { saveMeetingType } from '$lib/server/jafar/booking-types';
import { meetingTypeSchema } from '$lib/server/validation/booking.schema';

// Jafar business management E3: save or delete one meeting type. A type that has ever been booked cannot be
// deleted -- its visitors' links still need it -- so it is turned off instead.

const NOT_FOUND = 'That meeting type no longer exists.';

export const PATCH: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(NOT_FOUND);
	const parsed = await parseBody(event, meetingTypeSchema);
	if (!parsed.ok) return parsed.response;
	return saveMeetingType(getOwnerSupabaseClient(), event.params.id, parsed.data);
};

export const DELETE: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(NOT_FOUND);
	const { data, error } = await getOwnerSupabaseClient().rpc('owner_booking_delete_type', {
		target_type_id: event.params.id
	});
	if (error) {
		console.error('Could not delete the meeting type.', error);
		return databaseError();
	}
	if (data === 'unknown') return notFound(NOT_FOUND);
	if (data === 'booked')
		return validationError(
			{ form: 'This meeting has bookings, so it can only be turned off. Its links keep working.' },
			409
		);
	return json({ ok: true });
};
