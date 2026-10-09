import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { adoptTimeZone, isPlainRefusal, parseBody } from '$lib/server/jafar/calendar';
import { bookingSettingsSchema } from '$lib/server/validation/booking.schema';

// Jafar business management E1: Booking settings -- the public link on or off, the Discovery call, and Jafar's
// weekly hours. Not in any team area, so only Jafar reaches it (E3 opens hosts to teammates).

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
	const parsed = await parseBody(event, bookingSettingsSchema);
	if (!parsed.ok) return parsed.response;
	const { meeting_type: type, hours, enabled, time_zone } = parsed.data;
	const client = getOwnerSupabaseClient();

	try {
		// Open times are in Jafar's zone; the first save gives him the browser's when he has none.
		await adoptTimeZone(client, time_zone, undefined);
	} catch (error) {
		console.error('Could not save the time zone with the booking settings.', error);
		return databaseError();
	}

	const { data, error } = await client.rpc('owner_booking_save', {
		target_enabled: enabled,
		target_type_id: type.id,
		target_slug: type.slug,
		target_name: type.name,
		target_description: type.description ?? '',
		target_duration_minutes: type.duration_minutes,
		target_min_notice_minutes: type.min_notice_minutes,
		target_horizon_days: type.horizon_days,
		target_buffer_minutes: type.buffer_minutes,
		target_slot_interval_minutes: type.slot_interval_minutes,
		target_requires_approval: type.requires_approval,
		target_change_deadline_minutes: type.change_deadline_minutes,
		target_hours: hours
	});
	if (error?.code === '23505')
		return validationError({ 'meeting_type.slug': 'Another meeting already uses this link.' }, 409);
	if (isPlainRefusal(error)) return validationError({ form: error.message }, 409);
	if (error) {
		console.error('Could not save the booking settings.', error);
		return databaseError();
	}
	return json(data);
};
