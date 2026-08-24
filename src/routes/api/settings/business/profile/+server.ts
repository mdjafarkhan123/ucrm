import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { isStale, settingsWriteError, staleSettingsResponse } from '$lib/server/settings/errors';
import { businessProfileSchema } from '$lib/server/validation/settings.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { forgetOrganizationTimezone } from '$lib/server/requests/timezone';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.business.edit');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-profile-save:${organizationId}`,
			...SAVE_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = businessProfileSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const input = parsed.data;
	const { data, error } = await event.locals.supabase.rpc('save_organization_business_profile', {
		target_organization_id: organizationId,
		expected_revision: input.expected_revision,
		new_name: input.name,
		new_trade: input.trade,
		new_phone: input.phone,
		new_website: input.website,
		new_description: input.description,
		new_address_line1: input.address_line1,
		new_address_line2: input.address_line2,
		new_city: input.city,
		new_region: input.region,
		new_postal_code: input.postal_code,
		new_country_code: input.country_code,
		new_address_is_public: input.address_is_public,
		new_timezone: input.timezone,
		new_currency_code: input.currency_code,
		confirm_timezone: input.confirm_timezone,
		confirm_currency: input.confirm_currency
	});

	if (error) return settingsWriteError(error);
	if (isStale(data)) return staleSettingsResponse(data);

	// Timezone, currency, and locale are held in process for a few minutes for every request that has to
	// format a date or an amount. Without this, a saved change would not show up anywhere else in the app
	// until that window ran out.
	forgetOrganizationTimezone(organizationId);

	return json(data, { headers: NO_STORE_HEADERS });
};
