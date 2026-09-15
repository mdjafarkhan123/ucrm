import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { encodeInvoiceTaxCursor, readInvoiceTaxCursor } from '$lib/server/reports/invoice-tax';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { invoiceTaxReportQuerySchema } from '$lib/server/validation/financial-reports.schema';

type InvoiceTaxRow = {
	invoice_id: string;
	invoice_number: number;
	client_id: string;
	client_display_name: string | null;
	client_company_name: string | null;
	subject: string;
	tax_date: string;
	recognition_basis: 'issued' | 'paid_draft';
	currency_code: string;
	tax_source: string;
	tax_name: string | null;
	tax_rate_basis_points: number;
	net_sales_minor: number;
	tax_minor: number;
	total_minor: number;
	created_at: string;
};

type InvoiceTaxSummary = {
	net_sales_minor: number;
	tax_minor: number;
	billed_total_minor: number;
	invoice_count: number;
	taxed_invoice_count: number;
};

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.view');
	if ('response' in check) return check.response;
	if (!hasPermission(check.access, 'invoices.view_price')) {
		return json(
			{ error: 'You do not have access to invoice amounts.', reason: 'permission_denied' },
			{ status: 403 }
		);
	}

	const parsed = invoiceTaxReportQuerySchema.safeParse({
		from: event.url.searchParams.get('from') ?? undefined,
		to: event.url.searchParams.get('to') ?? undefined,
		cursor: event.url.searchParams.get('cursor') ?? undefined,
		limit: event.url.searchParams.get('limit') ?? undefined,
		direction: event.url.searchParams.get('direction') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const cursor = readInvoiceTaxCursor(parsed.data.cursor);
	if (parsed.data.cursor && (!cursor || cursor.direction !== parsed.data.direction)) {
		return validationError({ cursor: 'Start this report again.' });
	}

	const [pageResult, summaryResult] = await Promise.all([
		event.locals.supabase.rpc('financial_invoice_tax_page', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to,
			cursor_tax_date: cursor?.taxDate,
			cursor_invoice_id: cursor?.invoiceId,
			page_limit: parsed.data.limit + 1,
			sort_direction: parsed.data.direction
		}),
		event.locals.supabase.rpc('financial_invoice_tax_summary', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to
		})
	]);
	if (pageResult.error || summaryResult.error) return databaseError();

	const returned = (pageResult.data ?? []) as InvoiceTaxRow[];
	const summary = ((summaryResult.data ?? []) as InvoiceTaxSummary[])[0];
	if (!summary) return databaseError();
	const invoices = returned.slice(0, parsed.data.limit);
	const last = invoices.at(-1);

	return json(
		{
			from: parsed.data.from,
			to: parsed.data.to,
			direction: parsed.data.direction,
			summary,
			invoices,
			next_cursor:
				returned.length > parsed.data.limit && last
					? encodeInvoiceTaxCursor({
							direction: parsed.data.direction,
							taxDate: last.tax_date,
							invoiceId: last.invoice_id
						})
					: null
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
