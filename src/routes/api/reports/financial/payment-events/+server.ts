import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import {
	encodePaymentEventsCursor,
	readPaymentEventsCursor
} from '$lib/server/reports/payment-events';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { paymentEventsReportQuerySchema } from '$lib/server/validation/financial-reports.schema';

type PaymentEventRow = {
	event_id: string;
	client_id: string;
	client_display_name: string | null;
	client_company_name: string | null;
	event_type: 'received' | 'refunded' | 'reversed';
	original_event_type: 'received' | 'refunded' | null;
	event_date: string;
	amount_minor: number;
	cash_effect_minor: number;
	currency_code: string;
	method: string | null;
	reference: string | null;
	note: string | null;
	original_event_id: string | null;
	original_deposit_event_id: string | null;
	actor_user_id: string | null;
	created_at: string;
};

type PaymentEventsSummary = {
	received_minor: number;
	refunded_minor: number;
	reversed_receipt_minor: number;
	reversed_refund_minor: number;
	cash_effect_minor: number;
	event_count: number;
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

	const parsed = paymentEventsReportQuerySchema.safeParse({
		from: event.url.searchParams.get('from') ?? undefined,
		to: event.url.searchParams.get('to') ?? undefined,
		cursor: event.url.searchParams.get('cursor') ?? undefined,
		limit: event.url.searchParams.get('limit') ?? undefined,
		direction: event.url.searchParams.get('direction') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const cursor = readPaymentEventsCursor(parsed.data.cursor);
	if (parsed.data.cursor && (!cursor || cursor.direction !== parsed.data.direction)) {
		return validationError({ cursor: 'Start this report again.' });
	}

	const [pageResult, summaryResult] = await Promise.all([
		event.locals.supabase.rpc('financial_payment_events_page', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to,
			cursor_event_date: cursor?.eventDate,
			cursor_event_id: cursor?.eventId,
			page_limit: parsed.data.limit + 1,
			sort_direction: parsed.data.direction
		}),
		event.locals.supabase.rpc('financial_payment_events_summary', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to
		})
	]);
	if (pageResult.error || summaryResult.error) return databaseError();

	const returned = (pageResult.data ?? []) as PaymentEventRow[];
	const summary = ((summaryResult.data ?? []) as PaymentEventsSummary[])[0];
	if (!summary) return databaseError();
	const paymentEvents = returned.slice(0, parsed.data.limit);
	const last = paymentEvents.at(-1);

	return json(
		{
			from: parsed.data.from,
			to: parsed.data.to,
			direction: parsed.data.direction,
			summary,
			payment_events: paymentEvents,
			next_cursor:
				returned.length > parsed.data.limit && last
					? encodePaymentEventsCursor({
							direction: parsed.data.direction,
							eventDate: last.event_date,
							eventId: last.event_id
						})
					: null
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
