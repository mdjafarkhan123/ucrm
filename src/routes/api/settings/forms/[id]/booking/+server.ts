import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	validationError
} from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { formReadError, formWriteError } from '$lib/server/forms/errors';
import { formBookingSettingsSchema } from '$lib/server/validation/forms.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { isBookingOutcome, type BookableService, type BookingDetail } from '$lib/forms/types';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 40 };

type CatalogItemRow = {
	id: string;
	name: string;
	unit_price_minor: number;
	archived_at: string | null;
};

// Booking rules + bookable services + the org readiness facts the Booking tab needs to explain a greyed-out
// toggle (hours not set, service area not confirmed). Only assessment/job forms have any of this — reused
// from the Price Book's own service catalog, per 20260913160000 § 2.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.forms.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const formId = event.params.id;

	const { data: form, error: formError } = await event.locals.supabase
		.from('forms')
		.select('id, outcome')
		.eq('organization_id', organizationId)
		.eq('id', formId)
		.maybeSingle();

	if (formError) return formReadError(formError);
	if (!form) return notFound('That form could not be found.');
	if (!isBookingOutcome(form.outcome)) {
		return notFound('Only assessment and job forms have booking rules.');
	}

	const [rulesResult, servicesResult, orgResult] = await Promise.all([
		event.locals.supabase
			.from('form_booking_rules')
			.select(
				'requires_booking_approval, service_area_enabled, min_notice_minutes, slot_interval_minutes, visit_duration_minutes, arrival_window_minutes, buffer_minutes, revision'
			)
			.eq('form_id', formId)
			.maybeSingle(),
		event.locals.supabase
			.from('form_bookable_services')
			.select('catalog_item_id')
			.eq('form_id', formId)
			.order('position'),
		event.locals.supabase
			.from('organization_settings')
			.select('hours_mode, latitude, longitude, service_area_radius_miles')
			.eq('organization_id', organizationId)
			.maybeSingle()
	]);

	if (rulesResult.error || servicesResult.error || orgResult.error) return databaseError();
	if (!rulesResult.data) return notFound('This form has no booking rules.');

	// A plain lookup rather than an embed: the picker only ever needs a name (and the price, for parity with
	// the price list), and this sidesteps any ambiguity in how the client infers a to-one embed across the
	// table's composite foreign key.
	const catalogItemIds = (servicesResult.data ?? []).map((row) => row.catalog_item_id);
	const catalogItemsResult =
		catalogItemIds.length > 0
			? await event.locals.supabase
					.from('catalog_items')
					.select('id, name, unit_price_minor, archived_at')
					.in('id', catalogItemIds)
			: { data: [] as CatalogItemRow[], error: null };

	if (catalogItemsResult.error) return databaseError();
	const catalogItemsById = new Map(catalogItemsResult.data.map((item) => [item.id, item]));

	const services: BookableService[] = catalogItemIds.map((catalogItemId) => {
		const item = catalogItemsById.get(catalogItemId);
		return {
			catalog_item_id: catalogItemId,
			name: item?.name ?? 'Unknown service',
			unit_price_minor: item?.unit_price_minor ?? 0,
			archived_at: item?.archived_at ?? null
		};
	});

	const org = orgResult.data;
	const detail: BookingDetail = {
		rules: rulesResult.data,
		services,
		organization: {
			hours_set: org?.hours_mode != null && org.hours_mode !== 'not_configured',
			service_area_ready:
				org?.latitude != null && org?.longitude != null && org?.service_area_radius_miles != null
		}
	};

	return json(detail, { headers: PRIVATE_READ_HEADERS });
};

async function limited(event: Parameters<RequestHandler>[0], organizationId: string) {
	try {
		const limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-forms-booking-write:${organizationId}`,
			...SAVE_LIMIT
		});
		if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);
	} catch {
		return databaseError();
	}
	return null;
}

// One command saves rules + bookable services together — matches 4B-1's "one screen, one save" shape.
// Booking rules are not drafted/published like form content; a save here takes effect immediately.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.forms.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const rate = await limited(event, organizationId);
	if (rate) return rate;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = formBookingSettingsSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('update_form_booking_settings', {
		target_organization_id: organizationId,
		target_form_id: event.params.id,
		expected_revision: parsed.data.expected_revision,
		new_requires_booking_approval: parsed.data.requires_booking_approval,
		new_service_area_enabled: parsed.data.service_area_enabled,
		new_min_notice_minutes: parsed.data.min_notice_minutes,
		new_slot_interval_minutes: parsed.data.slot_interval_minutes,
		new_visit_duration_minutes: parsed.data.visit_duration_minutes,
		new_arrival_window_minutes: parsed.data.arrival_window_minutes,
		new_buffer_minutes: parsed.data.buffer_minutes,
		new_service_ids: parsed.data.service_ids
	});

	if (error) return formWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
