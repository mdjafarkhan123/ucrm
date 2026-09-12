import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	formBookingSlotsQuerySchema,
	BOOKING_PREVIEW_MAX_DAYS
} from '$lib/server/validation/forms.schema';
import type { BookingSlot } from '$lib/forms/types';

const NOT_AVAILABLE = { error: 'That form is not available.' };

// The public counterpart of the staff Booking tab's "sample available times" — same window cap, same
// underlying engine (get_public_form_available_slots -> private.compute_form_available_slots), just
// resolved by the form's public link instead of an authenticated organization.
export const GET: RequestHandler = async (event) => {
	const client = getOwnerSupabaseClient();
	const clientAddress = event.getClientAddress();
	const { orgSlug, formSlug } = event.params;

	const rateLimit = await checkRateLimit(client, {
		bucketKey: `public-form-slots:${orgSlug}:${formSlug}:${clientAddress}`,
		windowSeconds: 60,
		maxAttempts: 30
	});
	if (!rateLimit.allowed) return rateLimitedResponse(rateLimit.retryAfterSeconds);

	const parsed = formBookingSlotsQuerySchema.safeParse(
		Object.fromEntries(event.url.searchParams.entries())
	);
	if (!parsed.success) return json({ error: 'Give a valid date range.' }, { status: 422 });

	const start = new Date(`${parsed.data.range_start}T00:00:00Z`);
	const end = new Date(`${parsed.data.range_end}T00:00:00Z`);
	const spanDays = (end.getTime() - start.getTime()) / 86_400_000;
	if (!(spanDays >= 0) || spanDays > BOOKING_PREVIEW_MAX_DAYS) {
		return json(
			{ error: `Ask for at most ${BOOKING_PREVIEW_MAX_DAYS} days at a time.` },
			{ status: 422 }
		);
	}

	const { data, error } = await client.rpc('get_public_form_available_slots', {
		target_organization_slug: orgSlug,
		target_form_slug: formSlug,
		range_start: parsed.data.range_start,
		range_end: parsed.data.range_end
	});

	if (error) {
		if (error.code === '23514') return json(NOT_AVAILABLE, { status: 404 });
		console.error('Could not read public form availability.', error);
		return json({ error: 'We could not load available times. Please try again.' }, { status: 500 });
	}

	return json((data ?? []) as BookingSlot[], { headers: { 'cache-control': 'private, no-cache' } });
};
