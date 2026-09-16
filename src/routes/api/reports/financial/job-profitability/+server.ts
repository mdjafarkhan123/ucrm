import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import {
	encodeJobProfitabilityCursor,
	readJobProfitabilityCursor
} from '$lib/server/reports/job-profitability';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { jobProfitabilityReportQuerySchema } from '$lib/server/validation/financial-reports.schema';

// The database already returns these as null without jobs.view_cost; the route drops the keys so a reader
// without the permission never sees a cost-shaped column at all, let alone a zero.
const COST_ROW_KEYS = [
	'item_cost_minor',
	'labor_cost_minor',
	'expense_cost_minor',
	'total_cost_minor',
	'profit_minor',
	'margin_basis_points',
	'labor_minutes',
	'unrated_labor_count',
	'unrated_labor_minutes'
] as const;

const COST_SUMMARY_KEYS = [
	'item_cost_minor',
	'labor_cost_minor',
	'expense_cost_minor',
	'total_cost_minor',
	'profit_minor',
	'unpriced_cost_minor',
	'labor_minutes',
	'unrated_labor_count',
	'unrated_labor_minutes'
] as const;

type JobProfitabilityRow = {
	job_id: string;
	job_number: number;
	job_title: string;
	job_type: 'one_off' | 'recurring';
	price_basis: 'job_total' | 'per_visit' | 'fixed_per_period';
	job_status: string;
	closed_on: string | null;
	client_id: string;
	client_display_name: string | null;
	client_company_name: string | null;
	currency_code: string;
	unit_count: number | null;
	revenue_minor: number | null;
	item_cost_minor: number | null;
	labor_cost_minor: number | null;
	expense_cost_minor: number | null;
	total_cost_minor: number | null;
	profit_minor: number | null;
	margin_basis_points: number | null;
	labor_minutes: number | null;
	unrated_labor_count: number | null;
	unrated_labor_minutes: number | null;
};

type JobProfitabilitySummary = {
	job_count: number;
	one_off_count: number;
	per_visit_count: number;
	fixed_per_period_count: number;
	unpriced_job_count: number;
	revenue_minor: number;
	item_cost_minor: number | null;
	labor_cost_minor: number | null;
	expense_cost_minor: number | null;
	total_cost_minor: number | null;
	profit_minor: number | null;
	unpriced_cost_minor: number | null;
	labor_minutes: number | null;
	unrated_labor_count: number | null;
	unrated_labor_minutes: number | null;
};

function withoutKeys<T extends object>(record: T, keys: readonly (keyof T)[]) {
	const copy: Partial<T> = { ...record };
	for (const key of keys) delete copy[key];
	return copy;
}

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;
	if (!hasPermission(check.access, 'jobs.view_price')) {
		return json(
			{ error: 'You do not have access to job prices.', reason: 'permission_denied' },
			{ status: 403 }
		);
	}
	const costsVisible = hasPermission(check.access, 'jobs.view_cost');

	const parsed = jobProfitabilityReportQuerySchema.safeParse({
		from: event.url.searchParams.get('from') ?? undefined,
		to: event.url.searchParams.get('to') ?? undefined,
		cursor: event.url.searchParams.get('cursor') ?? undefined,
		limit: event.url.searchParams.get('limit') ?? undefined,
		direction: event.url.searchParams.get('direction') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const cursor = readJobProfitabilityCursor(parsed.data.cursor);
	if (parsed.data.cursor && (!cursor || cursor.direction !== parsed.data.direction)) {
		return validationError({ cursor: 'Start this report again.' });
	}

	const [pageResult, summaryResult] = await Promise.all([
		event.locals.supabase.rpc('financial_job_profitability_page', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to,
			cursor_job_number: cursor?.jobNumber,
			page_limit: parsed.data.limit + 1,
			sort_direction: parsed.data.direction
		}),
		event.locals.supabase.rpc('financial_job_profitability_summary', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to
		})
	]);
	if (pageResult.error || summaryResult.error) return databaseError();

	const returned = (pageResult.data ?? []) as JobProfitabilityRow[];
	const summary = ((summaryResult.data ?? []) as JobProfitabilitySummary[])[0];
	if (!summary) return databaseError();
	const jobs = returned.slice(0, parsed.data.limit);
	const last = jobs.at(-1);

	return json(
		{
			from: parsed.data.from,
			to: parsed.data.to,
			direction: parsed.data.direction,
			costs_visible: costsVisible,
			summary: costsVisible ? summary : withoutKeys(summary, COST_SUMMARY_KEYS),
			jobs: costsVisible ? jobs : jobs.map((row) => withoutKeys(row, COST_ROW_KEYS)),
			next_cursor:
				returned.length > parsed.data.limit && last
					? encodeJobProfitabilityCursor({
							direction: parsed.data.direction,
							jobNumber: last.job_number
						})
					: null
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
