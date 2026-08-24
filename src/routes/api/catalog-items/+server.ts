import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { encodeCursor, quoteFilterValue, readCursor } from '$lib/server/api/keyset';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	catalogItemCreateSchema,
	catalogListQuerySchema
} from '$lib/server/validation/quotes.schema';
import { catalogWriteError } from '$lib/server/quotes/errors';
import { catalogSelect } from '$lib/server/quotes/selects';

// The column each sort key actually walks. `name` reuses the picker's own
// `catalog_items_organization_name_idx`; `price` and `updated` each have a dedicated partial index added
// alongside `settings.price_book.manage`.
const SORT_COLUMNS = {
	name: 'name',
	price: 'unit_price_minor',
	updated: 'updated_at'
} as const;

// The price list, in name order by default, which is the order both the settings screen and the line-item
// picker want. Archived items are left out unless they are asked for: they are the part of this table that
// grows forever and neither screen shows them by default.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'catalog.view');
	if ('response' in check) return check.response;

	const parsed = catalogListQuerySchema.safeParse(
		Object.fromEntries(event.url.searchParams.entries())
	);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	const query = parsed.data;
	// Internal cost is exactly that. A member who prices work but may not see cost — sales and office, in
	// the seeded roles — never receives the column, and the price book simply shows no cost line.
	const canSeeCost = hasPermission(check.access, 'quotes.view_cost');
	const ascending = query.dir === 'asc';
	const sortColumn = SORT_COLUMNS[query.sort];

	let items = event.locals.supabase
		.from('catalog_items')
		.select(catalogSelect(canSeeCost))
		.eq('organization_id', check.auth.organization.id);

	if (!query.include_archived) items = items.is('archived_at', null);
	if (query.category) items = items.eq('category', query.category);
	if (query.labor) items = items.eq('is_labor', query.labor === 'only');
	if (query.taxable) items = items.eq('is_taxable', query.taxable === 'only');
	if (query.search) {
		// PostgREST treats %, _ and \ as pattern characters inside ilike, so a term carrying one has to
		// arrive escaped or it searches for something the person did not type. The settings list also
		// searches the description; both stay unindexed `ILIKE` on purpose -- a contractor's price book is
		// a bounded, per-tenant list, not a corpus that needs trigram or full-text support.
		const escaped = query.search.replace(/[\\%_]/g, (match) => `\\${match}`);
		items = items.or(`name.ilike.%${escaped}%,description.ilike.%${escaped}%`);
	}

	const cursor = readCursor(query.cursor);
	if (cursor) {
		// The seek is what the index actually scans on; the `or` then drops the cursor row itself and
		// anything tied with it on the wrong side of id.
		const quoted = quoteFilterValue(cursor.value);
		items = ascending
			? items
					.gte(sortColumn, cursor.value)
					.or(`${sortColumn}.gt.${quoted},and(${sortColumn}.eq.${quoted},id.gt.${cursor.id})`)
			: items
					.lte(sortColumn, cursor.value)
					.or(`${sortColumn}.lt.${quoted},and(${sortColumn}.eq.${quoted},id.lt.${cursor.id})`);
	}

	// One extra row answers "is there another page" without a second count query.
	const { data: rows, error } = await items
		.order(sortColumn, { ascending })
		.order('id', { ascending })
		.limit(query.limit + 1);
	if (error) return databaseError();

	const page = (rows ?? []).slice(0, query.limit);
	const last = page.at(-1) as Record<string, unknown> | undefined;
	return json(
		{
			items: page,
			next_cursor:
				(rows ?? []).length > query.limit && last
					? encodeCursor(last[sortColumn], last.id as string)
					: null,
			// The browser cannot tell "no cost sent" from "cost is zero", and an empty page carries no
			// items to infer it from, so the answer is stated outright.
			can_view_cost: canSeeCost,
			// Settings → Price Book is owner/administrator only even though this same list also backs the
			// Quote/Request picker's broader `catalog.view`. The Svelte page reads this instead of the
			// route it navigated from, so a person without the picker's own manage authority can never see
			// the management screen just by typing its URL.
			can_manage: hasPermission(check.access, 'settings.price_book.manage')
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// A new reusable default. Nothing already written down changes because of it — request lines and quote
// versions keep their own copies of whatever they were given.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'catalog.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = catalogItemCreateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase
		.from('catalog_items')
		.insert({
			organization_id: check.auth.organization.id,
			created_by: check.auth.user.id,
			...parsed.data
		})
		.select(catalogSelect(hasPermission(check.access, 'quotes.view_cost')))
		.single();

	if (error) return catalogWriteError(error);
	return json({ item: data }, { status: 201, headers: NO_STORE_HEADERS });
};
