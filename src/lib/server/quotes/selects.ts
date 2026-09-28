// Shared column list for the catalog routes. A `+server.ts` file may only export request handlers —
// SvelteKit's build rejects anything else — so this lives here instead of being exported from one route
// and imported into its sibling.
//
// Internal cost is never part of this list. `unit_cost_minor` left the `authenticated` grant entirely
// (20260910151000), so a select naming it would fail for everyone regardless of permission. A permitted
// reader gets cost back through `public.catalog_item_cost`, merged in by `attachCatalogCost` below.
export const CATALOG_SELECT = `id, category, name, description, unit_label, unit_price_minor,
	 is_taxable, is_labor, archived_at, created_at, updated_at, revision, updated_by, image_file_id` as const;
