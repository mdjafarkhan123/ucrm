import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { STORED_QUOTE_STATUSES } from '$lib/server/validation/quotes.schema';
import { organizationFormatting } from '$lib/server/requests/timezone';

// The Overview card on the Quotes list. Counted live, like the Requests card, so the numbers are never
// stale; the database groups and this route only fills in the statuses that had no rows so the card draws
// a zero instead of a gap.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.view');
	if ('response' in check) return check.response;

	// The organization's money format rides along. It is one cached row for the whole tenant, and the
	// new-quote form needs it before any quote exists to carry it.
	const [{ data, error }, formatting] = await Promise.all([
		event.locals.supabase.rpc('quote_status_counts', {
			target_organization_id: check.auth.organization.id
		}),
		organizationFormatting(event.locals.supabase, check.auth.organization.id)
	]);
	if (error) return databaseError();

	const counts = Object.fromEntries(STORED_QUOTE_STATUSES.map((status) => [status, 0])) as Record<
		string,
		number
	>;
	for (const row of data ?? []) {
		if (row.status in counts) counts[row.status] = Number(row.total);
	}

	return json(
		{
			counts,
			currency_code: formatting.ok ? formatting.formatting.currency_code : 'USD',
			locale: formatting.ok ? formatting.formatting.locale : 'en-US'
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
