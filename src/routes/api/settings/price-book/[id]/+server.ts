import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { catalogManageWriteError } from '$lib/server/quotes/errors';
import {
	priceBookItemDeleteSchema,
	priceBookItemUpdateSchema
} from '$lib/server/validation/quotes.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// Editing here replaces the whole item at once and is refused if it is stale -- the same shape Taxes uses,
// never the picker's own per-field PATCH at /api/catalog-items/[id].
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.price_book.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-price-book-update:${organizationId}`,
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

	const parsed = priceBookItemUpdateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('update_catalog_item', {
		target_organization_id: organizationId,
		target_item_id: event.params.id,
		expected_revision: parsed.data.expected_revision,
		new_category: parsed.data.category,
		new_name: parsed.data.name,
		new_description: parsed.data.description,
		new_unit_label: parsed.data.unit_label,
		new_is_labor: parsed.data.is_labor,
		new_unit_price_minor: parsed.data.unit_price_minor,
		new_unit_cost_minor: parsed.data.unit_cost_minor,
		new_is_taxable: parsed.data.is_taxable
	});

	if (error) return catalogManageWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};

// Permanent, on purpose (see the Part 2B migration): Request/Quote pricing lines already copied this
// item's name, price, and cost and keep that copy after the row is gone.
export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.price_book.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-price-book-delete:${organizationId}`,
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

	const parsed = priceBookItemDeleteSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('delete_catalog_item', {
		target_organization_id: organizationId,
		target_item_id: event.params.id,
		expected_revision: parsed.data.expected_revision
	});

	if (error) return catalogManageWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
