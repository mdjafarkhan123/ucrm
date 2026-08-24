import { hasPermission } from '$lib/server/access/permission';
import { resolveOrganizationAccess } from '$lib/server/access/effective';

// A quote's set can also hold headings and notes. They carry no catalog item and no cost, so they fall
// straight through; `line_kind` is named here only so the type accepts them alongside priced work.
type IncomingLine = {
	catalog_item_id?: string | null;
	unit_cost_minor?: number;
	line_kind?: string;
};

// Cost is internal, so somebody who may not see it never received it and cannot send it back. Their save
// would otherwise write a zero over the owner's real cost, and the profit on this work would quietly be
// wrong. The catalog item the line names still knows what it costs, so the server fills it in.
//
// Only a line that names a catalog item and arrives with no cost is touched. Nothing else can produce that
// combination, so a cost already frozen onto a line is never rewritten from a since-changed price list.
//
// Shared by request pricing and quote lines: one block edits both, so one rule protects both.
export async function withCatalogCost<T extends IncomingLine>(
	supabase: App.Locals['supabase'],
	organizationId: string,
	userId: string,
	lines: T[]
): Promise<T[]> {
	const blank = lines.filter((line) => line.catalog_item_id && !line.unit_cost_minor);
	if (blank.length === 0) return lines;

	// The price list is asked first because it is one indexed read. Working out who this person is costs
	// several, and there is no point paying for that when every candidate item costs nothing anyway —
	// which is the normal state of a price list nobody has entered costs into yet.
	const ids = [...new Set(blank.map((line) => line.catalog_item_id as string))];
	const { data, error } = await supabase
		.from('catalog_items')
		.select('id, unit_cost_minor')
		.eq('organization_id', organizationId)
		.in('id', ids);
	if (error || !data) return lines;

	const costs = new Map(
		data.filter((item) => item.unit_cost_minor > 0).map((item) => [item.id, item.unit_cost_minor])
	);
	if (costs.size === 0) return lines;

	try {
		const access = await resolveOrganizationAccess(supabase, organizationId, userId);
		if (hasPermission(access, 'quotes.view_cost')) return lines;
	} catch (accessError) {
		// A save is not the place to fail over a cost nobody asked to see. The line keeps what it sent.
		console.error('Could not resolve access while pricing.', accessError);
		return lines;
	}

	return lines.map((line) =>
		line.catalog_item_id && !line.unit_cost_minor && costs.has(line.catalog_item_id)
			? { ...line, unit_cost_minor: costs.get(line.catalog_item_id) as number }
			: line
	);
}
