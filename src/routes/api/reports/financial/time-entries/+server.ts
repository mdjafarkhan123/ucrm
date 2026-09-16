import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { encodeTimeEntriesCursor, readTimeEntriesCursor } from '$lib/server/reports/time-entries';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { timeEntriesReportQuerySchema } from '$lib/server/validation/financial-reports.schema';

// The database already returns these as null without jobs.view_cost; the route drops the keys so a reader
// without the permission never sees a money-shaped column at all, let alone a zero. Which rows they see —
// everyone's hours or only their own, and only assigned Jobs for the Field role — is decided by the
// definer readers, which restate the time-entry table's own policy.
const COST_ROW_KEYS = ['cost_per_hour_minor', 'cost_total_minor'] as const;
const COST_SUMMARY_KEYS = ['cost_total_minor'] as const;

type TimeEntryRow = {
	entry_id: string;
	started_at: string;
	started_on: string;
	minutes: number;
	user_id: string;
	user_name: string | null;
	job_id: string;
	job_number: number;
	job_title: string;
	client_id: string | null;
	client_display_name: string | null;
	client_company_name: string | null;
	visit_id: string | null;
	visit_date: string | null;
	currency_code: string;
	is_unrated: boolean;
	cost_per_hour_minor: number | null;
	cost_total_minor: number | null;
};

type TimeEntriesSummary = {
	entry_count: number;
	member_count: number;
	job_count: number;
	minutes: number;
	rated_minutes: number;
	unrated_count: number;
	unrated_minutes: number;
	cost_total_minor: number | null;
};

function withoutKeys<T extends object>(record: T, keys: readonly (keyof T)[]) {
	const copy: Partial<T> = { ...record };
	for (const key of keys) delete copy[key];
	return copy;
}

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;
	const teamVisible = hasPermission(check.access, 'time.track_team');
	if (!teamVisible && !hasPermission(check.access, 'time.track_own')) {
		return json(
			{ error: 'You do not have access to do that.', reason: 'permission_denied' },
			{ status: 403 }
		);
	}
	const costVisible = hasPermission(check.access, 'jobs.view_cost');

	const parsed = timeEntriesReportQuerySchema.safeParse({
		from: event.url.searchParams.get('from') ?? undefined,
		to: event.url.searchParams.get('to') ?? undefined,
		cursor: event.url.searchParams.get('cursor') ?? undefined,
		limit: event.url.searchParams.get('limit') ?? undefined,
		direction: event.url.searchParams.get('direction') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const cursor = readTimeEntriesCursor(parsed.data.cursor);
	if (parsed.data.cursor && (!cursor || cursor.direction !== parsed.data.direction)) {
		return validationError({ cursor: 'Start this report again.' });
	}

	const [pageResult, summaryResult] = await Promise.all([
		event.locals.supabase.rpc('financial_time_entries_page', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to,
			cursor_started_at: cursor?.startedAt,
			cursor_entry_id: cursor?.entryId,
			page_limit: parsed.data.limit + 1,
			sort_direction: parsed.data.direction
		}),
		event.locals.supabase.rpc('financial_time_entries_summary', {
			target_organization_id: check.auth.organization.id,
			report_from: parsed.data.from,
			report_to: parsed.data.to
		})
	]);
	if (pageResult.error || summaryResult.error) return databaseError();

	const returned = (pageResult.data ?? []) as TimeEntryRow[];
	const summary = ((summaryResult.data ?? []) as TimeEntriesSummary[])[0];
	if (!summary) return databaseError();
	const entries = returned.slice(0, parsed.data.limit);
	const last = entries.at(-1);

	return json(
		{
			from: parsed.data.from,
			to: parsed.data.to,
			direction: parsed.data.direction,
			team_visible: teamVisible,
			cost_visible: costVisible,
			summary: costVisible ? summary : withoutKeys(summary, COST_SUMMARY_KEYS),
			entries: costVisible ? entries : entries.map((row) => withoutKeys(row, COST_ROW_KEYS)),
			next_cursor:
				returned.length > parsed.data.limit && last
					? encodeTimeEntriesCursor({
							direction: parsed.data.direction,
							startedAt: last.started_at,
							entryId: last.entry_id
						})
					: null
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
