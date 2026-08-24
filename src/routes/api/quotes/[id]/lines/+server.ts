import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	validationError
} from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { replaceQuoteLinesSchema } from '$lib/server/validation/quotes.schema';
import { quoteWriteError } from '$lib/server/quotes/errors';
import { withCatalogCost } from '$lib/server/quotes/catalog-cost';
import { organizationFormatting } from '$lib/server/requests/timezone';

const NOT_FOUND = 'That quote could not be found.';

const LINE_SELECT = `id, position, source_catalog_item_id, category, is_labor, name, description,
	 unit_label, quantity, is_taxable, image_attachment_id, line_kind, selection_kind,
	 is_recommended`;

const PRICE_COLUMNS = 'unit_price_minor, line_total_minor';
const COST_COLUMNS = 'unit_cost_minor, line_cost_total_minor';

// Money a person may not see is never selected in the first place. Dropping it after the fact would still
// have carried it over the wire, and a payload that never held it cannot leak it.
function columns(base: string, ...extra: Array<string | null>) {
	return [base, ...extra.filter(Boolean)].join(', ');
}

// The quote's twin of the request pricing route, so one Products & Services block can read and write
// either document. The revision comes back with the lines: it is what the next save sends to prove it is
// editing the version it was shown.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.view');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const supabase = event.locals.supabase;
	const canSeePrice = hasPermission(check.access, 'quotes.view_price');
	const canSeeCost = hasPermission(check.access, 'quotes.view_cost');

	const { data: quote, error } = await supabase
		.from('quotes')
		.select('id, status, draft_version_id')
		.eq('organization_id', organizationId)
		.eq('id', event.params.id)
		.maybeSingle();
	if (error) return databaseError();
	if (!quote) return notFound(NOT_FOUND);

	const versionId = quote.draft_version_id;
	const [{ data: version, error: versionError }, { data: lines, error: linesError }, formatting] =
		await Promise.all([
			versionId
				? supabase
						.from('quote_versions')
						.select(columns('id, revision', canSeePrice ? 'subtotal_minor' : null))
						.eq('organization_id', organizationId)
						.eq('id', versionId)
						.maybeSingle()
				: Promise.resolve({ data: null, error: null }),
			versionId
				? supabase
						.from('quote_version_lines')
						.select(
							columns(
								LINE_SELECT,
								canSeePrice ? PRICE_COLUMNS : null,
								canSeeCost ? COST_COLUMNS : null
							)
						)
						.eq('organization_id', organizationId)
						.eq('quote_id', quote.id)
						.eq('quote_version_id', versionId)
						.order('position', { ascending: true })
						.order('id', { ascending: true })
				: Promise.resolve({ data: [], error: null }),
			// The block shows money in the organization's own currency, and this is the one row for the
			// whole tenant, cached in process rather than fetched again per request.
			organizationFormatting(supabase, organizationId)
		]);
	if (versionError || linesError) return databaseError();

	const draft = version as { revision?: number; subtotal_minor?: number } | null;
	return json(
		{
			revision: draft?.revision ?? null,
			subtotal_minor: canSeePrice ? (draft?.subtotal_minor ?? 0) : null,
			// Only a draft can be typed into. Everything else is a document somebody has already been
			// shown, and the write function refuses it too.
			editable: quote.status === 'draft',
			lines: lines ?? [],
			currency_code: formatting.ok ? formatting.formatting.currency_code : 'USD',
			locale: formatting.ok ? formatting.formatting.locale : 'en-US'
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// The whole set is replaced in one call. Nothing here recalculates a line total or a subtotal — those are
// generated columns, and `replace_quote_version_lines` is the only thing allowed to write these rows.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = replaceQuoteLinesSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const lines = await withCatalogCost(
		event.locals.supabase,
		check.auth.organization.id,
		check.auth.user.id,
		parsed.data.lines
	);

	const { data, error } = await event.locals.supabase.rpc('replace_quote_version_lines', {
		target_quote_id: event.params.id,
		expected_revision: parsed.data.expected_revision,
		new_lines: lines
	});

	if (error) return quoteWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
