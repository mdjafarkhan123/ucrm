import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { outcomeReportQuerySchema } from '$lib/server/validation/pipeline.schema';
import { resolveDateRange } from '$lib/server/pipeline/board';
import { organizationFormatting } from '$lib/server/requests/timezone';
import {
	orderStageTimes,
	type QuoteCounts,
	type RawStageTime,
	type RequestCounts,
	type WorkCounts
} from '$lib/pipeline/conversion';

type ConversionAnswer = {
	requests: RequestCounts;
	quotes: QuoteCounts;
	sources: (WorkCounts & { lead_source: string | null; won_value?: number | null })[];
	stages: RawStageTime[];
	can_view_sources: boolean;
	can_view_value: boolean;
};

// The Sales Outcomes conversion numbers: what became of the work CREATED in the chosen window. The same
// date controls as the outcome numbers, read against created date instead of outcome date. The database
// re-checks pipeline access, withholds money from a member without pipeline.view_value, and withholds the
// lead-source breakdown from a member who may not see every client.
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

	const { data, error } = await event.locals.supabase.rpc('pipeline_conversion_report', {
		target_organization_id: check.auth.organization.id,
		report_from: range.from ?? undefined,
		report_to: range.to ?? undefined
	});
	if (error || !data) return databaseError();

	const answer = data as unknown as ConversionAnswer;

	return json(
		{
			requests: answer.requests,
			quotes: answer.quotes,
			sources: answer.sources,
			// Left to right as the board draws its columns, each stage carrying its own name.
			stages: orderStageTimes(answer.stages),
			can_view_sources: answer.can_view_sources,
			can_view_value: answer.can_view_value,
			currency_code: formatting.currency_code,
			locale: formatting.locale,
			timezone: formatting.timezone
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
