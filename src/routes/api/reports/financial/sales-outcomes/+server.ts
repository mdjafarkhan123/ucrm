import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import {
	encodeSalesOutcomesCursor,
	readSalesOutcomesCursor
} from '$lib/server/reports/sales-outcomes';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { salesOutcomesReportQuerySchema } from '$lib/server/validation/financial-reports.schema';

// The database already returns these as null without pipeline.view_value; the route drops the keys so a
// reader without the permission never sees a value-shaped column at all, let alone a zero.
const VALUE_ROW_KEYS = ['estimated_value_minor'] as const;
const VALUE_SUMMARY_KEYS = ['won_value_minor', 'lost_value_minor'] as const;

type SalesOutcomeRow = {
	opportunity_id: string;
	outcome: 'won' | 'lost';
	outcome_at: string;
	outcome_on: string;
	created_on: string;
	source_kind: 'request' | 'quote';
	request_id: string | null;
	quote_id: string | null;
	quote_number: number | null;
	title: string;
	client_id: string;
	client_display_name: string | null;
	client_company_name: string | null;
	currency_code: string;
	estimated_value_minor: number | null;
	lost_reason: string | null;
	outcome_event_id: string | null;
};

type SalesOutcomesSummary = {
	won_count: number;
	lost_count: number;
	won_unvalued_count: number;
	lost_unvalued_count: number;
	won_value_minor: number | null;
	lost_value_minor: number | null;
};

function withoutKeys<T extends object>(record: T, keys: readonly (keyof T)[]) {
	const copy: Partial<T> = { ...record };
	for (const key of keys) delete copy[key];
	return copy;
}

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;
	const valuesVisible = hasPermission(check.access, 'pipeline.view_value');

	const parsed = salesOutcomesReportQuerySchema.safeParse({
		from: event.url.searchParams.get('from') ?? undefined,
		to: event.url.searchParams.get('to') ?? undefined,
		cursor: event.url.searchParams.get('cursor') ?? undefined,
		limit: event.url.searchParams.get('limit') ?? undefined,
		direction: event.url.searchParams.get('direction') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const cursor = readSalesOutcomesCursor(parsed.data.cursor);
	if (parsed.data.cursor && (!cursor || cursor.direction !== parsed.data.direction)) {
		return validationError({ cursor: 'Start this report again.' });
	}

	const [pageResult, summaryResult] = await Promise.all([
		event.locals.supabase.rpc('financial_sales_outcomes_page', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to,
			cursor_outcome_at: cursor?.outcomeAt,
			cursor_opportunity_id: cursor?.opportunityId,
			page_limit: parsed.data.limit + 1,
			sort_direction: parsed.data.direction
		}),
		event.locals.supabase.rpc('financial_sales_outcomes_summary', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to
		})
	]);
	if (pageResult.error || summaryResult.error) return databaseError();

	const returned = (pageResult.data ?? []) as SalesOutcomeRow[];
	const summary = ((summaryResult.data ?? []) as SalesOutcomesSummary[])[0];
	if (!summary) return databaseError();
	const outcomes = returned.slice(0, parsed.data.limit);
	const last = outcomes.at(-1);

	return json(
		{
			from: parsed.data.from,
			to: parsed.data.to,
			direction: parsed.data.direction,
			values_visible: valuesVisible,
			summary: valuesVisible ? summary : withoutKeys(summary, VALUE_SUMMARY_KEYS),
			outcomes: valuesVisible ? outcomes : outcomes.map((row) => withoutKeys(row, VALUE_ROW_KEYS)),
			next_cursor:
				returned.length > parsed.data.limit && last
					? encodeSalesOutcomesCursor({
							direction: parsed.data.direction,
							outcomeAt: last.outcome_at,
							opportunityId: last.opportunity_id
						})
					: null
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
