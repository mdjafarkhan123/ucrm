import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	buildCatalogExportCsv,
	catalogExportFileName,
	fetchCatalogExportData
} from '$lib/server/exports/catalog-export';

// Onboarding & Data Portability, Part 3: download the whole Price Book as one CSV. The mirror of Part 2's
// client export, sized down to what a single flat table needs -- no zip, no manifest.
const EXPORT_LIMIT = { windowSeconds: 60, maxAttempts: 5 };

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.price_book.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `price-book-export:${organizationId}`,
			...EXPORT_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	let csv: string;
	try {
		const items = await fetchCatalogExportData(event.locals.supabase, organizationId);
		csv = buildCatalogExportCsv(items);
	} catch (error) {
		console.error('Could not build the Price Book export.', error);
		return databaseError();
	}

	return new Response(csv, {
		headers: {
			'content-type': 'text/csv; charset=utf-8',
			'content-disposition': `attachment; filename="${catalogExportFileName()}"`,
			'cache-control': 'no-store'
		}
	});
};
