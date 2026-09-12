import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, validationError } from '$lib/server/api/errors';
import { formReadError } from '$lib/server/forms/errors';
import {
	BOOKING_PREVIEW_MAX_DAYS,
	formBookingSlotsQuerySchema
} from '$lib/server/validation/forms.schema';
import type { BookingSlot } from '$lib/forms/types';

// The "sample available times" card on the Booking tab. Recommendation approved 2026-09-13: the preview
// reflects the real, saved rules via the same engine 4B-2b built (public.get_form_available_slots) rather
// than a second "what-if" computation — refresh it after Save, not on every keystroke. No new database code.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.forms.manage');
	if ('response' in check) return check.response;

	const parsed = formBookingSlotsQuerySchema.safeParse(
		Object.fromEntries(event.url.searchParams.entries())
	);
	if (!parsed.success) return validationError({ form: 'Give a valid date range.' });

	const start = new Date(`${parsed.data.range_start}T00:00:00Z`);
	const end = new Date(`${parsed.data.range_end}T00:00:00Z`);
	const spanDays = (end.getTime() - start.getTime()) / 86_400_000;
	if (!(spanDays >= 0) || spanDays > BOOKING_PREVIEW_MAX_DAYS) {
		return validationError({ form: `Ask for at most ${BOOKING_PREVIEW_MAX_DAYS} days at a time.` });
	}

	const { data, error } = await event.locals.supabase.rpc('get_form_available_slots', {
		target_organization_id: check.auth.organization.id,
		target_form_id: event.params.id,
		range_start: parsed.data.range_start,
		range_end: parsed.data.range_end
	});

	if (error) return formReadError(error);
	return json((data ?? []) as BookingSlot[], { headers: PRIVATE_READ_HEADERS });
};
