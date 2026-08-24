// Shared column lists for the catalog routes. A `+server.ts` file may only export request handlers —
// SvelteKit's build rejects anything else — so this lives here instead of being exported from one route
// and imported into its sibling.
//
// Internal cost is not part of the base list. Money a person may not see is never selected in the first
// place, the same rule the quote route follows: a payload that never held it cannot leak it. Both lists
// are written out in full because the generated types read the literal text of the select.
const CATALOG_SELECT = `id, category, name, description, unit_label, unit_price_minor,
	 is_taxable, is_labor, archived_at, created_at, updated_at, revision, updated_by` as const;

const CATALOG_SELECT_WITH_COST = `id, category, name, description, unit_label, unit_price_minor,
	 unit_cost_minor, is_taxable, is_labor, archived_at, created_at, updated_at, revision, updated_by` as const;

// The row type describes the widest shape, because the generated types cannot parse a select that is one
// of two strings. What comes back really does drop `unit_cost_minor` when cost is withheld, which is why
// the browser's own `CatalogItem` type has it optional.
export function catalogSelect(canSeeCost: boolean) {
	return (
		canSeeCost ? CATALOG_SELECT_WITH_COST : CATALOG_SELECT
	) as typeof CATALOG_SELECT_WITH_COST;
}
