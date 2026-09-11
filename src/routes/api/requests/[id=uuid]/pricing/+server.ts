import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	unauthorized,
	validationError
} from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { replaceRequestPricingSchema } from '$lib/server/validation/quotes.schema';
import { requestPricingWriteError } from '$lib/server/quotes/errors';
import { withCatalogCost, preserveRequestLineCost } from '$lib/server/quotes/catalog-cost';
import { organizationFormatting } from '$lib/server/requests/timezone';
import { asMoneyMap, withMoney } from '$lib/server/quotes/money';

const NOT_FOUND = 'That request could not be found.';

// unit_cost_minor and line_cost_total_minor are never named here: they left the `authenticated` grant
// (20260910151500), so a select naming them would fail for everyone regardless of permission. A permitted
// reader gets them back through public.request_pricing_line_money, merged in below.
const LINE_SELECT = `id, position, catalog_item_id, category, is_labor, name, description, unit_label,
	 quantity, unit_price_minor, is_taxable, line_total_minor, image_attachment_id`;

// The Products & Services and Labor blocks read this on their own rather than riding along with the
// request detail, because the revision has to come back with the lines: it is what the next save sends to
// prove it is editing the version it was shown.
export const GET: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const organizationId = auth.organization.id;
	const supabase = event.locals.supabase;
	const requestId = event.params.id;

	const [
		{ data: request, error: requestError },
		{ data: lines, error: linesError },
		formatting,
		{ data: lineMoney, error: lineMoneyError }
	] = await Promise.all([
		supabase
			.from('requests')
			.select('id, status, pricing_revision, pricing_subtotal_minor')
			.eq('organization_id', organizationId)
			.eq('id', requestId)
			.maybeSingle(),
		supabase
			.from('request_pricing_lines')
			.select(LINE_SELECT)
			.eq('organization_id', organizationId)
			.eq('request_id', requestId)
			.order('position', { ascending: true })
			.order('id', { ascending: true }),
		// The pricing block has to show money in the organization's own currency, and this is the one
		// row for the whole tenant, cached in process rather than fetched again per request.
		organizationFormatting(supabase, organizationId),
		// Cost is not in the select above (it left the authenticated grant): a permitted reader gets it
		// back from this gated function instead, keyed by line id. An empty object comes back for anyone
		// without quotes.view_cost, which is a no-op merge.
		supabase.rpc('request_pricing_line_money', { target_request_id: requestId })
	]);

	if (requestError || linesError || lineMoneyError) return databaseError();
	if (!request) return notFound(NOT_FOUND);

	return json(
		{
			revision: request.pricing_revision,
			subtotal_minor: request.pricing_subtotal_minor,
			// Pricing is frozen once a request has become a quote or been archived; the write function
			// refuses either, and the form needs to know before it lets someone start typing.
			editable: request.status !== 'converted' && request.status !== 'archived',
			lines: withMoney((lines ?? []) as unknown as Array<{ id: string }>, asMoneyMap(lineMoney)),
			currency_code: formatting.ok ? formatting.formatting.currency_code : 'USD',
			locale: formatting.ok ? formatting.formatting.locale : 'en-US'
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// The whole set is replaced in one call. Nothing here recalculates a line total or a subtotal — those are
// generated columns, and `replace_request_pricing_lines` is the only thing allowed to write these rows.
export const PATCH: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = replaceRequestPricingSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const preserved = await preserveRequestLineCost(
		event.locals.supabase,
		auth.organization.id,
		auth.user.id,
		event.params.id,
		parsed.data.lines
	);
	const lines = await withCatalogCost(
		event.locals.supabase,
		auth.organization.id,
		auth.user.id,
		preserved
	);

	const { data, error } = await event.locals.supabase.rpc('replace_request_pricing_lines', {
		target_request_id: event.params.id,
		expected_revision: parsed.data.expected_revision,
		new_lines: lines
	});

	if (error) return requestPricingWriteError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
