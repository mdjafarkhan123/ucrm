import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import {
	encodeUninvoicedWorkCursor,
	readUninvoicedWorkCursor
} from '$lib/server/reports/uninvoiced-work';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { uninvoicedWorkReportQuerySchema } from '$lib/server/validation/financial-reports.schema';

type UninvoicedWorkRow = {
	unit_kind: 'visit' | 'period' | 'job';
	unit_id: string;
	work_date: string;
	job_id: string;
	job_number: number;
	job_title: string;
	price_basis: 'job_total' | 'per_visit' | 'fixed_per_period';
	client_id: string;
	client_display_name: string | null;
	client_company_name: string | null;
	currency_code: string;
	uninvoiced_minor: number;
	visit_id: string | null;
	reminder_id: string | null;
};

type UninvoicedWorkSummary = {
	uninvoiced_minor: number;
	unit_count: number;
	visit_count: number;
	period_count: number;
	job_count: number;
	distinct_job_count: number;
};

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;
	if (!hasPermission(check.access, 'jobs.view_price')) {
		return json(
			{ error: 'You do not have access to job prices.', reason: 'permission_denied' },
			{ status: 403 }
		);
	}

	const parsed = uninvoicedWorkReportQuerySchema.safeParse({
		from: event.url.searchParams.get('from') ?? undefined,
		to: event.url.searchParams.get('to') ?? undefined,
		cursor: event.url.searchParams.get('cursor') ?? undefined,
		limit: event.url.searchParams.get('limit') ?? undefined,
		direction: event.url.searchParams.get('direction') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const cursor = readUninvoicedWorkCursor(parsed.data.cursor);
	if (parsed.data.cursor && (!cursor || cursor.direction !== parsed.data.direction)) {
		return validationError({ cursor: 'Start this report again.' });
	}

	const [pageResult, summaryResult] = await Promise.all([
		event.locals.supabase.rpc('financial_uninvoiced_work_page', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to,
			cursor_work_date: cursor?.workDate,
			cursor_unit_id: cursor?.unitId,
			page_limit: parsed.data.limit + 1,
			sort_direction: parsed.data.direction
		}),
		event.locals.supabase.rpc('financial_uninvoiced_work_summary', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to
		})
	]);
	if (pageResult.error || summaryResult.error) return databaseError();

	const returned = (pageResult.data ?? []) as UninvoicedWorkRow[];
	const summary = ((summaryResult.data ?? []) as UninvoicedWorkSummary[])[0];
	if (!summary) return databaseError();
	const units = returned.slice(0, parsed.data.limit);
	const last = units.at(-1);

	return json(
		{
			from: parsed.data.from,
			to: parsed.data.to,
			direction: parsed.data.direction,
			summary,
			units,
			next_cursor:
				returned.length > parsed.data.limit && last
					? encodeUninvoicedWorkCursor({
							direction: parsed.data.direction,
							workDate: last.work_date,
							unitId: last.unit_id
						})
					: null
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
