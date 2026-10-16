import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { readQuoteListOverview } from '$lib/quotes/list-overview';

// The Quotes list's Open quotes card money, its follow-up strip and the Conversion card. Every figure is
// worked out by `quote_list_overview` in the database; the function also withholds money from a reader
// without quotes.view_price, so this route only passes the answer through in a known shape. Kept apart from
// /api/quotes/counts so the new-quote form, which reads counts for its money format, does not pay for it.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('quote_list_overview', {
		target_organization_id: check.auth.organization.id
	});
	if (error) return databaseError();

	return json(readQuoteListOverview(data), { headers: PRIVATE_READ_HEADERS });
};
