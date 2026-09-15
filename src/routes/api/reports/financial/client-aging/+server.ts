import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { encodeClientAgingCursor, readClientAgingCursor } from '$lib/server/reports/client-aging';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { clientAgingReportQuerySchema } from '$lib/server/validation/financial-reports.schema';

type ClientAgingRow = {
	client_id: string;
	client_display_name: string | null;
	client_company_name: string | null;
	sort_name: string;
	currency_code: string;
	outstanding_minor: number;
	not_due_minor: number;
	overdue_1_30_minor: number;
	overdue_31_60_minor: number;
	overdue_61_90_minor: number;
	overdue_91_plus_minor: number;
	available_credit_minor: number;
	client_balance_minor: number;
	open_invoice_count: number;
};

type ClientAgingSummary = Omit<
	ClientAgingRow,
	'client_id' | 'client_display_name' | 'client_company_name' | 'sort_name' | 'currency_code'
> & { client_count: number };

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.view');
	if ('response' in check) return check.response;
	if (!hasPermission(check.access, 'invoices.view_price')) {
		return json(
			{ error: 'You do not have access to invoice amounts.', reason: 'permission_denied' },
			{ status: 403 }
		);
	}

	const parsed = clientAgingReportQuerySchema.safeParse({
		asOf: event.url.searchParams.get('as_of') ?? undefined,
		cursor: event.url.searchParams.get('cursor') ?? undefined,
		limit: event.url.searchParams.get('limit') ?? undefined,
		direction: event.url.searchParams.get('direction') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const cursor = readClientAgingCursor(parsed.data.cursor);
	if (parsed.data.cursor && (!cursor || cursor.direction !== parsed.data.direction)) {
		return validationError({ cursor: 'Start this report again.' });
	}

	const [pageResult, summaryResult] = await Promise.all([
		event.locals.supabase.rpc('financial_client_aging_page', {
			target_organization_id: check.auth.organization.id,
			report_as_of: parsed.data.asOf,
			cursor_sort_name: cursor?.sortName,
			cursor_client_id: cursor?.clientId,
			page_limit: parsed.data.limit + 1,
			sort_direction: parsed.data.direction
		}),
		event.locals.supabase.rpc('financial_client_aging_summary', {
			target_organization_id: check.auth.organization.id,
			report_as_of: parsed.data.asOf
		})
	]);
	if (pageResult.error || summaryResult.error) return databaseError();

	const returned = (pageResult.data ?? []) as ClientAgingRow[];
	const summary = ((summaryResult.data ?? []) as ClientAgingSummary[])[0];
	if (!summary) return databaseError();
	const clients = returned.slice(0, parsed.data.limit);
	const last = clients.at(-1);

	return json(
		{
			as_of: parsed.data.asOf,
			direction: parsed.data.direction,
			summary,
			clients,
			next_cursor:
				returned.length > parsed.data.limit && last
					? encodeClientAgingCursor({
							direction: parsed.data.direction,
							sortName: last.sort_name,
							clientId: last.client_id
						})
					: null
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
