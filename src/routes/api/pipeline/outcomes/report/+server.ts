import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { outcomeReportQuerySchema } from '$lib/server/validation/pipeline.schema';
import { resolveDateRange } from '$lib/server/pipeline/board';
import { loadLostReasons, lostReasonLabeller } from '$lib/server/pipeline/lost-reasons';
import { organizationFormatting } from '$lib/server/requests/timezone';

type ReportGroup = { count: number; unvalued_count: number; value_total?: number | null };
type OutcomesReport = {
	won: ReportGroup;
	lost: ReportGroup;
	direct_job: ReportGroup;
	days_to_win: { count: number; median: number | null; average: number | null };
	lost_reasons: { reason: string | null; count: number }[];
};

// The Sales Outcomes headline numbers for the same outcome-date window the list below them uses. The
// database re-checks pipeline access and withholds money from a member without pipeline.view_value; this
// route validates the window and gives each Lost reason its name.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;

	const query = event.url.searchParams;
	const parsed = outcomeReportQuerySchema.safeParse({
		date: query.get('date') ?? undefined,
		from: query.get('from') ?? undefined,
		to: query.get('to') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const formattingLookup = await organizationFormatting(check.auth.organization.id);
	if (!formattingLookup.ok) return databaseError();
	const { formatting } = formattingLookup;

	let range: { from: string | null; to: string | null } = { from: null, to: null };
	if (parsed.data.date !== 'all') {
		range = resolveDateRange(parsed.data.date, formatting.timezone, {
			from: parsed.data.from,
			to: parsed.data.to
		});
	}

	const [reportResult, reasonsLookup] = await Promise.all([
		event.locals.supabase.rpc('pipeline_outcomes_report', {
			target_organization_id: check.auth.organization.id,
			report_from: range.from ?? undefined,
			report_to: range.to ?? undefined
		}),
		loadLostReasons(event.locals.supabase, check.auth.organization.id)
	]);
	if (reportResult.error || !reasonsLookup.ok || !reportResult.data) return databaseError();

	const report = reportResult.data as unknown as OutcomesReport;
	const reasonLabel = lostReasonLabeller(reasonsLookup.reasons);

	return json(
		{
			...report,
			// The breakdown always adds up to the Lost count: a customer's own decline and "no reason" are
			// their own lines, named here so the page does not have to know the keys.
			lost_reasons: report.lost_reasons.map((line) => ({
				reason: line.reason,
				label:
					line.reason === 'customer_declined'
						? 'Customer declined'
						: (reasonLabel(line.reason) ?? 'No reason given'),
				count: line.count
			})),
			can_view_value: 'value_total' in report.won,
			currency_code: formatting.currency_code,
			locale: formatting.locale,
			timezone: formatting.timezone
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
