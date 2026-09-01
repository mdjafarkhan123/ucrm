import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { JOB_DERIVED_STATUSES } from '$lib/server/validation/jobs.schema';
import { organizationFormatting } from '$lib/server/requests/timezone';

// The Overview card on the Jobs list. Counted live, like the Quotes card, so the numbers are never stale;
// the database groups the same view the list draws and this route only fills in the statuses that had no
// rows so the card draws a zero instead of a gap.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	// The organization's money format rides along. It is one cached row for the whole tenant.
	const [{ data, error }, formatting] = await Promise.all([
		event.locals.supabase.rpc('job_status_counts', {
			target_organization_id: check.auth.organization.id
		}),
		organizationFormatting(event.locals.supabase, check.auth.organization.id)
	]);
	if (error) return databaseError();

	const counts = Object.fromEntries(JOB_DERIVED_STATUSES.map((status) => [status, 0])) as Record<
		string,
		number
	>;
	for (const row of data ?? []) {
		if (row.derived_status in counts) counts[row.derived_status] = Number(row.total);
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
