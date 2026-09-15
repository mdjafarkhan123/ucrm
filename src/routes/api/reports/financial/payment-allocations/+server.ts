import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import {
	encodePaymentAllocationsCursor,
	readPaymentAllocationsCursor
} from '$lib/server/reports/payment-allocations';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { paymentAllocationsReportQuerySchema } from '$lib/server/validation/financial-reports.schema';

type PaymentAllocationRow = {
	allocation_id: string;
	invoice_id: string;
	invoice_number: number;
	client_id: string;
	client_display_name: string | null;
	client_company_name: string | null;
	entry_type: 'applied' | 'unapplied';
	amount_minor: number;
	allocation_effect_minor: number;
	currency_code: string;
	source_type: 'payment' | 'quote_deposit';
	source_event_id: string;
	reversed_allocation_id: string | null;
	reason: string | null;
	actor_user_id: string | null;
	activity_date: string;
	created_at: string;
};

type PaymentAllocationsSummary = {
	applied_minor: number;
	unapplied_minor: number;
	net_allocated_minor: number;
	entry_count: number;
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

	const parsed = paymentAllocationsReportQuerySchema.safeParse({
		from: event.url.searchParams.get('from') ?? undefined,
		to: event.url.searchParams.get('to') ?? undefined,
		cursor: event.url.searchParams.get('cursor') ?? undefined,
		limit: event.url.searchParams.get('limit') ?? undefined,
		direction: event.url.searchParams.get('direction') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const cursor = readPaymentAllocationsCursor(parsed.data.cursor);
	if (parsed.data.cursor && (!cursor || cursor.direction !== parsed.data.direction)) {
		return validationError({ cursor: 'Start this report again.' });
	}

	const [pageResult, summaryResult] = await Promise.all([
		event.locals.supabase.rpc('financial_payment_allocations_page', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to,
			cursor_created_at: cursor?.createdAt,
			cursor_allocation_id: cursor?.allocationId,
			page_limit: parsed.data.limit + 1,
			sort_direction: parsed.data.direction
		}),
		event.locals.supabase.rpc('financial_payment_allocations_summary', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to
		})
	]);
	if (pageResult.error || summaryResult.error) return databaseError();

	const returned = (pageResult.data ?? []) as PaymentAllocationRow[];
	const summary = ((summaryResult.data ?? []) as PaymentAllocationsSummary[])[0];
	if (!summary) return databaseError();
	const allocations = returned.slice(0, parsed.data.limit);
	const last = allocations.at(-1);

	return json(
		{
			from: parsed.data.from,
			to: parsed.data.to,
			direction: parsed.data.direction,
			summary,
			allocations,
			next_cursor:
				returned.length > parsed.data.limit && last
					? encodePaymentAllocationsCursor({
							direction: parsed.data.direction,
							createdAt: last.created_at,
							allocationId: last.allocation_id
						})
					: null
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
