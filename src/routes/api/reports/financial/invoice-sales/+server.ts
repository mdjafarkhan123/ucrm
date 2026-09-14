import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import {
	encodeInvoiceSalesCursor,
	readInvoiceSalesCursor
} from '$lib/server/reports/invoice-sales';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { invoiceSalesReportQuerySchema } from '$lib/server/validation/financial-reports.schema';

type InvoiceSalesRow = {
	invoice_id: string;
	invoice_number: number;
	root_invoice_id: string;
	predecessor_invoice_id: string | null;
	client_id: string;
	client_display_name: string | null;
	client_company_name: string | null;
	subject: string;
	sale_date: string;
	recognition_basis: 'issued' | 'paid_draft';
	currency_code: string;
	net_sales_minor: number;
	tax_minor: number;
	total_minor: number;
	written_off_at: string | null;
	has_unsettled_legacy_closure: boolean;
	created_at: string;
};

type InvoiceSalesSummary = {
	net_sales_minor: number;
	tax_minor: number;
	billed_total_minor: number;
	write_off_count: number;
	historical_status_only_closure_count: number;
};

// One bounded page of current billed sales. The database rechecks both financial permissions and tenant
// ownership, then reads the frozen Invoice facts that the future CSV will use too.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.view');
	if ('response' in check) return check.response;
	if (!hasPermission(check.access, 'invoices.view_price')) {
		return json(
			{ error: 'You do not have access to invoice amounts.', reason: 'permission_denied' },
			{ status: 403 }
		);
	}

	const parsed = invoiceSalesReportQuerySchema.safeParse({
		from: event.url.searchParams.get('from') ?? undefined,
		to: event.url.searchParams.get('to') ?? undefined,
		cursor: event.url.searchParams.get('cursor') ?? undefined,
		limit: event.url.searchParams.get('limit') ?? undefined,
		direction: event.url.searchParams.get('direction') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const cursor = readInvoiceSalesCursor(parsed.data.cursor);
	if (parsed.data.cursor && (!cursor || cursor.direction !== parsed.data.direction)) {
		return validationError({ cursor: 'Start this report again.' });
	}

	const [pageResult, summaryResult] = await Promise.all([
		event.locals.supabase.rpc('financial_invoice_sales_page', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to,
			cursor_sale_date: cursor?.saleDate,
			cursor_invoice_id: cursor?.invoiceId,
			page_limit: parsed.data.limit + 1,
			sort_direction: parsed.data.direction
		}),
		event.locals.supabase.rpc('financial_invoice_sales_summary', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to
		})
	]);
	if (pageResult.error || summaryResult.error) return databaseError();

	const returned = (pageResult.data ?? []) as InvoiceSalesRow[];
	const summary = ((summaryResult.data ?? []) as InvoiceSalesSummary[])[0];
	if (!summary) return databaseError();
	const sales = returned.slice(0, parsed.data.limit);
	const last = sales.at(-1);
	const nextCursor =
		returned.length > parsed.data.limit && last
			? encodeInvoiceSalesCursor({
					direction: parsed.data.direction,
					saleDate: last.sale_date,
					invoiceId: last.invoice_id
				})
			: null;

	return json(
		{
			from: parsed.data.from,
			to: parsed.data.to,
			direction: parsed.data.direction,
			summary,
			sales,
			next_cursor: nextCursor
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
