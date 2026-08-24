import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { catalogManageWriteError } from '$lib/server/quotes/errors';
import { catalogItemCreateSchema } from '$lib/server/validation/quotes.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// A new Price Book item, Owner/Administrator only. The picker's own POST at /api/catalog-items stays
// exactly as it is: a Quote editor still adds a saved item from the drawer with `catalog.edit`, unprotected
// by revision, exactly as approved for that slice.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.price_book.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-price-book-create:${organizationId}`,
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

	const parsed = catalogItemCreateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('create_catalog_item', {
		target_organization_id: organizationId,
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
	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};
