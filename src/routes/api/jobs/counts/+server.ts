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
	const organizationId = check.auth.organization.id;
	const formatting = await organizationFormatting(organizationId);
	const timezone = formatting.ok ? formatting.formatting.timezone : 'UTC';
	// "Today" is the business's own calendar day, the same day the Jobs status uses.
	const today = new Intl.DateTimeFormat('en-CA', { timeZone: timezone }).format(new Date());
	const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

	const [{ data, error }, visitsToday, completedRecently, money] = await Promise.all([
		event.locals.supabase.rpc('job_status_counts', { target_organization_id: organizationId }),
		event.locals.supabase
			.from('job_visits')
			.select('id', { count: 'exact', head: true })
			.eq('organization_id', organizationId)
			.eq('visit_date', today),
		event.locals.supabase
			.from('job_visits')
			.select('id', { count: 'exact', head: true })
			.eq('organization_id', organizationId)
			.gte('completed_at', thirtyDaysAgo),
		event.locals.supabase.rpc('invoice_money_overview', { target_organization_id: organizationId })
	]);
	if (error || visitsToday.error || completedRecently.error) return databaseError();

	// Money a reader may not see comes back as a dash, never a wrong number; a role without invoice access
	// simply has no figure to show here.
	const moneyRow = money.error
		? null
		: (money.data as {
				collected_this_month_minor: number | null;
				outstanding_minor: number | null;
			} | null);
	const collected = moneyRow?.collected_this_month_minor ?? null;
	const outstanding = moneyRow?.outstanding_minor ?? null;

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
			visits_today: visitsToday.count ?? 0,
			completed_past_30_days: completedRecently.count ?? 0,
			collected_this_month_minor: collected,
			outstanding_minor: outstanding,
			currency_code: formatting.ok ? formatting.formatting.currency_code : 'USD',
			locale: formatting.ok ? formatting.formatting.locale : 'en-US'
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
