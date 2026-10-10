import { json } from '@sveltejs/kit';
import type { Json } from '$lib/database.types';
import { databaseError, validationError } from '$lib/server/api/errors';
import type { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { HOST_REFUSED, unqualifiedHosts } from '$lib/server/jafar/booking-hosts';
import { isPlainRefusal } from '$lib/server/jafar/calendar';
import type { MeetingTypeBody } from '$lib/server/validation/booking.schema';

// Jafar business management E3: adding or saving a meeting type, shared by its two routes.

type Client = ReturnType<typeof getOwnerSupabaseClient>;

export async function saveMeetingType(client: Client, id: string | null, type: MeetingTypeBody) {
	try {
		if ((await unqualifiedHosts(client, type.host_member_ids)).length)
			return validationError({ host_member_ids: HOST_REFUSED }, 409);
		const { data, error } = await client.rpc('owner_booking_save_type', {
			// The generated types cannot say a uuid argument takes null; the function adds a type for null.
			target_type_id: id as string,
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
			target_is_active: type.is_active,
			target_host_member_id: type.host_member_id as string,
			target_host_member_ids: type.host_member_ids as Json,
			target_visitor_reminder_minutes: type.visitor_reminder_minutes,
			target_location_kind: type.location_kind,
			target_video_link_mode: type.video_link_mode
		});
		if (error?.code === '23505')
			return validationError({ slug: 'Another meeting already uses this link.' }, 409);
		if (isPlainRefusal(error)) return validationError({ form: error.message }, 409);
		if (error) throw error;
		return json(data);
	} catch (error) {
		console.error('Could not save the meeting type.', error);
		return databaseError();
	}
}
