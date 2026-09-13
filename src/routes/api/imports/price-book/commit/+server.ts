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
	type CatalogReviewRow,
	type ExistingCatalogItem
} from '$lib/server/imports/catalog-review';

// Onboarding & Data Portability, Part 3, step 3: write the plan. Recomputes it fresh against the current
// database (the same function Review used, seconds or minutes earlier) rather than trusting anything the
// browser echoed back, then executes every create/update in small concurrent batches -- there is no queue and
// no worker, so this one request has to finish the whole file. A price book is realistically small enough
// that a handful of batches of RPC calls settle in well under the length of one request.
const COMMIT_LIMIT = { windowSeconds: 60, maxAttempts: 5 };
const WRITE_CONCURRENCY = 10;

type DatabaseError = { code?: string; message?: string };

// The plain-string mirror of catalogManageWriteError -- that helper builds a whole HTTP Response for a single
// request; here each row needs its own message without aborting the batch.
function describeWriteError(error: DatabaseError): string {
	if (error.code === '42501') return 'You do not have access to manage the Price Book.';
	if (error.code === 'P0409') return 'This item changed since you reviewed. Import it again.';
	if (error.code === '23505') return error.message ?? 'That name is already in use.';
	if (error.code === '23514') return error.message ?? 'That change is not allowed.';
	return 'This row could not be saved.';
}

async function mapWithConcurrency<T, R>(
	items: T[],
	limit: number,
	run: (item: T) => Promise<R>
): Promise<R[]> {
	const results: R[] = new Array(items.length);
	let next = 0;
	async function worker() {
		while (true) {
			const index = next++;
			if (index >= items.length) return;
			results[index] = await run(items[index]);
		}
	}
	await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
	return results;
}

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.price_book.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const supabase = event.locals.supabase;

	let limit;
	try {
		limit = await checkRateLimit(supabase, {
			bucketKey: `price-book-import-commit:${organizationId}`,
			...COMMIT_LIMIT
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

	const { data: existingRows, error: readError } = await supabase.rpc(
		'catalog_items_for_price_book_import',
		{ target_organization_id: organizationId }
	);
	if (readError) return databaseError();

	const existingByName = new Map<string, ExistingCatalogItem>();
	for (const row of (existingRows ?? []) as unknown as ExistingCatalogItem[]) {
		const key = normalizeCatalogName(row.name);
		if (!existingByName.has(key)) existingByName.set(key, row);
	}

	const { rows: plan } = runCatalogReview({
		rows: parsed.data.rows,
		mapping: parsed.data.column_mapping,
		matchAction: parsed.data.match_action,
		existingByName
	});

	const counts = { created: 0, updated: 0, skipped: 0, held: 0, error: 0 };
	const errorRows: { source_row_number: number; reason: string }[] = [];

	const writable = plan.filter(
		(
			row
		): row is CatalogReviewRow & {
			resolved_item: NonNullable<CatalogReviewRow['resolved_item']>;
		} => row.planned_action === 'create' || row.planned_action === 'update'
	);

	await mapWithConcurrency(writable, WRITE_CONCURRENCY, async (row) => {
		const item = row.resolved_item;
		if (row.planned_action === 'create') {
			const { error } = await supabase.rpc('create_catalog_item', {
				target_organization_id: organizationId,
				new_category: item.category,
				new_name: item.name,
				new_description: item.description,
				new_unit_label: item.unit_label,
				new_is_labor: item.is_labor,
				new_unit_price_minor: item.unit_price_minor,
				new_unit_cost_minor: item.unit_cost_minor,
				new_is_taxable: item.is_taxable
			});
			if (error) {
				counts.error += 1;
				errorRows.push({
					source_row_number: row.source_row_number,
					reason: describeWriteError(error)
				});
			} else {
				counts.created += 1;
			}
			return;
		}

		const { error } = await supabase.rpc('update_catalog_item', {
			target_organization_id: organizationId,
			target_item_id: row.match_item_id,
			expected_revision: row.match_revision,
			new_category: item.category,
			new_name: item.name,
			new_description: item.description,
			new_unit_label: item.unit_label,
			new_is_labor: item.is_labor,
			new_unit_price_minor: item.unit_price_minor,
			new_unit_cost_minor: item.unit_cost_minor,
			new_is_taxable: item.is_taxable
		});
		if (error) {
			counts.error += 1;
			errorRows.push({
				source_row_number: row.source_row_number,
				reason: describeWriteError(error)
			});
		} else {
			counts.updated += 1;
		}
	});

	for (const row of plan) {
		if (row.planned_action === 'skip') counts.skipped += 1;
		else if (row.planned_action === 'hold') {
			counts.held += 1;
			errorRows.push({
				source_row_number: row.source_row_number,
				reason: row.flags.includes('duplicate_name_in_file')
					? 'Another row earlier in this file already uses this name.'
					: 'This row needs a decision and was not imported.'
			});
		} else if (row.planned_action === 'error') {
			counts.error += 1;
			errorRows.push({
				source_row_number: row.source_row_number,
				reason: row.error_message ?? 'This row could not be read.'
			});
		}
	}

	errorRows.sort((a, b) => a.source_row_number - b.source_row_number);

	return json({ counts, error_rows: errorRows }, { headers: NO_STORE_HEADERS });
};
