import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { INVOICE_DERIVED_STATUSES } from '$lib/server/validation/invoices.schema';
import { organizationFormatting } from '$lib/server/requests/timezone';

// The Overview card on the Invoices list. Counted live, like the Jobs and Quotes cards, so the numbers are
// never stale; the database derives each label from the same rule the list draws and this route only fills in
// the statuses that had no rows so the card draws a zero instead of a gap.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.view');
	if ('response' in check) return check.response;

	const [{ data, error }, { data: money, error: moneyError }, formatting] = await Promise.all([
		event.locals.supabase.rpc('invoice_status_counts', {
			target_organization_id: check.auth.organization.id
		}),
		event.locals.supabase.rpc('invoice_money_overview', {
			target_organization_id: check.auth.organization.id
		}),
		organizationFormatting(check.auth.organization.id)
	]);
	if (error || moneyError) return databaseError();

	const counts = Object.fromEntries(
		INVOICE_DERIVED_STATUSES.map((status) => [status, 0])
	) as Record<string, number>;
	for (const row of (data ?? []) as { derived_status: string; total: number }[]) {
		if (row.derived_status in counts) counts[row.derived_status] = Number(row.total);
	}

	const moneyRow = (money ?? {}) as {
		outstanding_minor: number | null;
		overdue_minor: number | null;
		collected_this_month_minor: number | null;
	};

	return json(
		{
			counts,
			outstanding_minor: moneyRow.outstanding_minor ?? null,
			overdue_minor: moneyRow.overdue_minor ?? null,
			collected_this_month_minor: moneyRow.collected_this_month_minor ?? null,
			currency_code: formatting.ok ? formatting.formatting.currency_code : 'USD',
			locale: formatting.ok ? formatting.formatting.locale : 'en-US'
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
