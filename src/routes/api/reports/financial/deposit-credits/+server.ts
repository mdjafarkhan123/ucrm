import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import {
	encodeDepositCreditsCursor,
	readDepositCreditsCursor
} from '$lib/server/reports/deposit-credits';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { depositCreditsReportQuerySchema } from '$lib/server/validation/financial-reports.schema';

type DepositCreditRow = {
	event_id: string;
	quote_id: string;
	quote_number: number;
	quote_version_id: string;
	client_id: string;
	client_display_name: string | null;
	client_company_name: string | null;
	event_type: 'received' | 'reversed';
	amount_minor: number;
	cash_effect_minor: number;
	currency_code: string;
	method: 'cash' | 'check' | 'other';
	reference: string | null;
	note: string | null;
	reversed_event_id: string | null;
	refunded_minor: number;
	allocated_minor: number;
	available_credit_minor: number;
	actor_user_id: string | null;
	activity_date: string;
	created_at: string;
};

type DepositCreditsSummary = {
	received_minor: number;
	reversed_minor: number;
	cash_effect_minor: number;
	refunded_minor: number;
	allocated_minor: number;
	available_credit_minor: number;
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

	const parsed = depositCreditsReportQuerySchema.safeParse({
		from: event.url.searchParams.get('from') ?? undefined,
		to: event.url.searchParams.get('to') ?? undefined,
		cursor: event.url.searchParams.get('cursor') ?? undefined,
		limit: event.url.searchParams.get('limit') ?? undefined,
		direction: event.url.searchParams.get('direction') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const cursor = readDepositCreditsCursor(parsed.data.cursor);
	if (parsed.data.cursor && (!cursor || cursor.direction !== parsed.data.direction)) {
		return validationError({ cursor: 'Start this report again.' });
	}

	const [pageResult, summaryResult] = await Promise.all([
		event.locals.supabase.rpc('financial_deposit_credits_page', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to,
			cursor_created_at: cursor?.createdAt,
			cursor_event_id: cursor?.eventId,
			page_limit: parsed.data.limit + 1,
			sort_direction: parsed.data.direction
		}),
		event.locals.supabase.rpc('financial_deposit_credits_summary', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to
		})
	]);
	if (pageResult.error || summaryResult.error) return databaseError();

	const returned = (pageResult.data ?? []) as DepositCreditRow[];
	const summary = ((summaryResult.data ?? []) as DepositCreditsSummary[])[0];
	if (!summary) return databaseError();
	const deposits = returned.slice(0, parsed.data.limit);
	const last = deposits.at(-1);

	return json(
		{
			from: parsed.data.from,
			to: parsed.data.to,
			direction: parsed.data.direction,
			summary,
			deposits,
			next_cursor:
				returned.length > parsed.data.limit && last
					? encodeDepositCreditsCursor({
							direction: parsed.data.direction,
							createdAt: last.created_at,
							eventId: last.event_id
						})
					: null
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
