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
import { asMoneyMap, withMoney } from '$lib/server/quotes/money';

const NOT_FOUND = 'That quote could not be found.';

const LINE_SELECT = `id, position, source_catalog_item_id, category, is_labor, name, description,
	 unit_label, quantity, is_taxable, image_attachment_id, line_kind, selection_kind,
	 is_recommended`;

// Money is not on these rows to select. `authenticated` lost the grant on the money columns, so the
// subtotal and the per-line money come back from `quote_version_money` and `quote_line_money`, which
// apply `quotes.view_price` and `quotes.view_cost` in the database.

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
	const wantsMoney = canSeePrice || canSeeCost;
	const [
		{ data: version, error: versionError },
		{ data: lines, error: linesError },
		formatting,
		{ data: versionMoney, error: versionMoneyError },
		{ data: lineMoney, error: lineMoneyError }
	] = await Promise.all([
		versionId
			? supabase
					.from('quote_versions')
					.select('id, revision')
					.eq('organization_id', organizationId)
					.eq('id', versionId)
					.maybeSingle()
			: Promise.resolve({ data: null, error: null }),
		versionId
			? supabase
					.from('quote_version_lines')
					.select(LINE_SELECT)
					.eq('organization_id', organizationId)
					.eq('quote_id', quote.id)
					.eq('quote_version_id', versionId)
					.order('position', { ascending: true })
					.order('id', { ascending: true })
			: Promise.resolve({ data: [], error: null }),
		// The block shows money in the organization's own currency, and this is the one row for the
		// whole tenant, cached in process rather than fetched again per request.
		organizationFormatting(supabase, organizationId),
		wantsMoney && versionId
			? supabase.rpc('quote_version_money', { target_version_ids: [versionId] })
			: Promise.resolve({ data: {}, error: null }),
		wantsMoney && versionId
			? supabase.rpc('quote_line_money', { target_version_id: versionId })
			: Promise.resolve({ data: {}, error: null })
	]);
	if (versionError || linesError || versionMoneyError || lineMoneyError) return databaseError();

	const draft = version as { revision?: number } | null;
	const draftMoney = versionId ? (asMoneyMap(versionMoney)[versionId] ?? {}) : {};
	const subtotal = draftMoney.subtotal_minor;
	return json(
		{
			revision: draft?.revision ?? null,
			subtotal_minor: canSeePrice ? (typeof subtotal === 'number' ? subtotal : 0) : null,
			// Only a draft can be typed into. Everything else is a document somebody has already been
			// shown, and the write function refuses it too.
			editable: quote.status === 'draft',
			lines: withMoney((lines ?? []) as unknown as Array<{ id: string }>, asMoneyMap(lineMoney)),
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
