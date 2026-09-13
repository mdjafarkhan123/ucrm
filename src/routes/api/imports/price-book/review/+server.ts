import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { importCatalogReviewSchema } from '$lib/server/validation/imports.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	normalizeCatalogName,
	runCatalogReview,
	type ExistingCatalogItem
} from '$lib/server/imports/catalog-review';

// Onboarding & Data Portability, Part 3, step 2: the dry run. Recomputes the whole plan fresh from the rows,
// mapping, and match action the browser sends -- there is no batch to look up, so this and Commit are the
// same computation, just with Commit going on to write.
const REVIEW_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.price_book.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `price-book-import-review:${organizationId}`,
			...REVIEW_LIMIT
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

	const parsed = importCatalogReviewSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data: existingRows, error } = await event.locals.supabase.rpc(
		'catalog_items_for_price_book_import',
		{ target_organization_id: organizationId }
	);
	if (error) return databaseError();

	const existingByName = new Map<string, ExistingCatalogItem>();
	for (const row of (existingRows ?? []) as unknown as ExistingCatalogItem[]) {
		// If two active items already share a name (possible: no DB constraint stops it directly, only
		// create/update do), the earliest-created one wins the match -- deterministic, and the office can
		// still see and fix the other one in Settings.
		const key = normalizeCatalogName(row.name);
		if (!existingByName.has(key)) existingByName.set(key, row);
	}

	const { summary } = runCatalogReview({
		rows: parsed.data.rows,
		mapping: parsed.data.column_mapping,
		matchAction: parsed.data.match_action,
		existingByName
	});

	return json({ summary }, { headers: NO_STORE_HEADERS });
};
