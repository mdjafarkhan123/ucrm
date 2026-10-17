import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { Database } from '$lib/database.types';
import { requireClientPermission } from '$lib/server/access/clients';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { organizationTimezone } from '$lib/server/requests/timezone';
import { clientOverviewWindows } from '$lib/server/clients/overview';

type PopularTagRow = Database['public']['Functions']['client_popular_tags']['Returns'][number];

// The two cards above the Clients list: the Client book (leads, customers, archived, popular tags) and the
// dark New clients card. Counted live by the database in one trip (two RPCs side by side); this route
// only works out the calendar windows in the organization's timezone and shapes the answer.
// Same permission as the list itself, so whoever sees the numbers sees the clients they count.
export const GET: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.view');
	if ('response' in access) return access.response;

	const organizationId = access.auth.organization.id;
	const supabase = event.locals.supabase;
	const timezone = await organizationTimezone(organizationId);
	const windows = clientOverviewWindows(timezone);

	const [{ data: countRows, error: countsError }, { data: tagRows, error: tagsError }] =
		await Promise.all([
			supabase.rpc('client_overview_counts', {
				target_organization_id: organizationId,
				current_since: windows.current_since,
				previous_since: windows.previous_since,
				year_since: windows.year_since
			}),
			supabase.rpc('client_popular_tags', { target_organization_id: organizationId, tag_limit: 4 })
		]);
	if (countsError || tagsError) return databaseError();

	const counts = countRows?.[0];
	return json(
		{
			counts: {
				lead: Number(counts?.leads ?? 0),
				customer: Number(counts?.customers ?? 0),
				archived: Number(counts?.archived ?? 0)
			},
			popular_tags: (tagRows ?? []).map((row: PopularTagRow) => ({
				id: row.tag_id,
				name: row.name,
				total: Number(row.total)
			})),
			new_clients: {
				current: Number(counts?.new_clients_current ?? 0),
				previous: Number(counts?.new_clients_previous ?? 0),
				period: windows.period
			},
			new_leads_30_days: Number(counts?.new_leads_current ?? 0),
			new_clients_this_year: Number(counts?.new_clients_year ?? 0)
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
