import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { adoptTimeZone, parseBody } from '$lib/server/jafar/calendar';
import { bookingEnabledSchema } from '$lib/server/validation/booking.schema';

// Jafar business management E1/E3: Booking settings -- read them all, or turn the public link on or off. Meeting
// types and each host's hours save through their own routes. Not in any team area, so only Jafar reaches it.

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const { data, error } = await getOwnerSupabaseClient().rpc('owner_booking_settings');
	if (error) {
		console.error('Could not load the booking settings.', error);
		return json({ error: 'Booking settings could not be loaded.' }, { status: 500 });
	}
	return json(data, { headers: PRIVATE_READ_HEADERS });
};

export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const parsed = await parseBody(event, bookingEnabledSchema);
	if (!parsed.ok) return parsed.response;
	const client = getOwnerSupabaseClient();
	try {
		// Open times are in Jafar's zone; the first save gives him the browser's when he has none.
		await adoptTimeZone(client, parsed.data.time_zone, undefined);
		const { data, error } = await client.rpc('owner_booking_set_enabled', {
			target_enabled: parsed.data.enabled
		});
		if (error) throw error;
		return json(data);
	} catch (error) {
		console.error('Could not save the booking link switch.', error);
		return databaseError();
	}
};
