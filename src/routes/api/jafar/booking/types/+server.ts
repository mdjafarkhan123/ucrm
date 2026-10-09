import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { parseBody } from '$lib/server/jafar/calendar';
import { saveMeetingType } from '$lib/server/jafar/booking-types';
import { meetingTypeSchema } from '$lib/server/validation/booking.schema';

// Jafar business management E3: add a meeting type. Only Jafar reaches Booking settings.

export const POST: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const parsed = await parseBody(event, meetingTypeSchema);
	if (!parsed.ok) return parsed.response;
	return saveMeetingType(getOwnerSupabaseClient(), null, parsed.data);
};
