import { hasPermission } from '$lib/server/access/permission';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

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
	//
	// `unit_cost_minor` is not in the `authenticated` grant (20260910151000): this fill-in exists precisely
	// for a session that cannot see cost, so it has to read past that grant on purpose rather than through
	// it. The owner client is the trusted, server-only boundary that can — the permission decision below is
	// still what governs whether the cost actually reaches this caller's line.
	const ids = [...new Set(blank.map((line) => line.catalog_item_id as string))];
	const { data, error } = await getOwnerSupabaseClient()
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

// A cost-blind save must never overwrite a line's existing real cost with whatever it sent — usually zero,
// since it never saw the real number. The browser already carries each existing line's own id through every
// edit, so that id is how the server tells "this line, unchanged" from "a brand new line" and restores the
// real cost for the former. Run this before `withCatalogCost`, so a new line is the only kind still blank by
// the time that catalog fill-in runs. Request pricing only: quote and job lines are a separate write path
// this does not touch.
export async function preserveRequestLineCost<
	T extends { id?: string | null; unit_cost_minor?: number }
>(
	supabase: App.Locals['supabase'],
	organizationId: string,
	userId: string,
	requestId: string,
	lines: T[]
): Promise<T[]> {
	const existingIds = [
		...new Set(lines.map((line) => line.id).filter((id): id is string => Boolean(id)))
	];
	if (existingIds.length === 0) return lines;

	try {
		const access = await resolveOrganizationAccess(supabase, organizationId, userId);
		if (hasPermission(access, 'quotes.view_cost')) return lines;
	} catch (accessError) {
		console.error('Could not resolve access while pricing.', accessError);
		return lines;
	}

	// Same reasoning as `withCatalogCost`: this exists precisely for a session that cannot see cost, so it
	// reads past the `authenticated` grant on purpose through the owner client.
	const { data, error } = await getOwnerSupabaseClient()
		.from('request_pricing_lines')
		.select('id, unit_cost_minor')
		.eq('organization_id', organizationId)
		.eq('request_id', requestId)
		.in('id', existingIds);
	if (error || !data) return lines;

	const costs = new Map(data.map((row) => [row.id, row.unit_cost_minor]));
	return lines.map((line) =>
		line.id && costs.has(line.id)
			? { ...line, unit_cost_minor: costs.get(line.id) as number }
			: line
	);
}

// Cost for the Price Book screens, gated the same way the quote and job money readers are: a select can
// never name `unit_cost_minor` any more (20260910151000), so a permitted viewer gets it back through
// `public.catalog_item_cost` instead, merged onto the rows the caller already fetched without it.
export async function attachCatalogCost<T extends { id: string }>(
	supabase: App.Locals['supabase'],
	canSeeCost: boolean,
	items: T[]
): Promise<(T & { unit_cost_minor?: number })[]> {
	if (!canSeeCost || items.length === 0) return items;

	const { data, error } = await supabase.rpc('catalog_item_cost', {
		target_item_ids: items.map((item) => item.id)
	});
	if (error || !data) return items;

	const costs = data as Record<string, number>;
	return items.map((item) =>
		item.id in costs ? { ...item, unit_cost_minor: costs[item.id] } : item
	);
}
