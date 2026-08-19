import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { outcomePageQuerySchema } from '$lib/server/validation/pipeline.schema';
import { resolveDateRange } from '$lib/server/pipeline/board';
import { encodeOutcomeCursor, readOutcomeCursor } from '$lib/server/pipeline/outcomes-report';
import { organizationFormatting } from '$lib/server/requests/timezone';

type OutcomePageRow = {
	id: string;
	title: string;
	outcome: string;
	created_at: string;
	outcome_at: string;
	client_id: string;
	client_display_name: string | null;
	client_company_name: string | null;
	estimated_value: number | null;
};

// The Sales Outcomes report: one closed outcome type at a time, paged and sorted through
// `pipeline_outcome_page`, which re-applies tenant, pipeline access, client visibility and money the same
// way `pipeline_board_page` does -- this route shapes the answer, it does not guard it.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;

	const query = event.url.searchParams;
	const parsed = outcomePageQuerySchema.safeParse({
		type: query.get('type') ?? undefined,
		cursor: query.get('cursor') ?? undefined,
		limit: query.get('limit') ?? undefined,
		sort: query.get('sort') ?? undefined,
		direction: query.get('direction') ?? undefined,
		date: query.get('date') ?? undefined,
		from: query.get('from') ?? undefined,
		to: query.get('to') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { type, limit, sort, direction, date } = parsed.data;
	const canViewValue = hasPermission(check.access, 'pipeline.view_value');
	const canViewClients = hasPermission(check.access, 'customers.view');

	// Ordering by Total or Client is reading privileged data -- money, or a client the caller may not
	// otherwise see -- so both are refused here as well as in the database, the same way the board refuses
	// sorting by value for a member without it.
	if (sort === 'total' && !canViewValue) {
		return json({ error: 'You cannot sort Sales Outcomes by total.' }, { status: 403 });
	}
	if (sort === 'client' && !canViewClients) {
		return json({ error: 'You cannot sort Sales Outcomes by client.' }, { status: 403 });
	}

	const cursor = readOutcomeCursor(parsed.data.cursor);
	if (parsed.data.cursor && (!cursor || cursor.sort !== sort)) {
		return validationError({ cursor: 'Start this report again.' });
	}

	let range: { from: string | null; to: string | null } = { from: null, to: null };
	if (date !== 'all') {
		const formattingLookup = await organizationFormatting(
			event.locals.supabase,
			check.auth.organization.id
		);
		if (!formattingLookup.ok) return databaseError();
		range = resolveDateRange(date, formattingLookup.formatting.timezone, {
			from: parsed.data.from,
			to: parsed.data.to
		});
	}

	const { data: rows, error } = await event.locals.supabase.rpc('pipeline_outcome_page', {
		target_organization_id: check.auth.organization.id,
		outcome_type: type,
		page_limit: limit + 1,
		sort_key: sort,
		sort_direction: direction,
		outcome_from: range.from ?? undefined,
		outcome_to: range.to ?? undefined,
		cursor_sort_key: cursor?.sort,
		cursor_phase: cursor?.phase,
		cursor_timestamp:
			cursor && (cursor.sort === 'created' || cursor.sort === 'outcome_at')
				? cursor.value
				: undefined,
		cursor_numeric: cursor && cursor.sort === 'total' ? Number(cursor.value) : undefined,
		cursor_text:
			cursor && (cursor.sort === 'title' || cursor.sort === 'client') ? cursor.value : undefined,
		cursor_id: cursor?.id
	});
	if (error) return databaseError();

	const returned = (rows ?? []) as OutcomePageRow[];
	const page = returned.slice(0, limit);
	const hasMore = returned.length > limit;

	const outcomes = page.map((row) => ({
		id: row.id,
		title: row.title,
		outcome: row.outcome,
		created_at: row.created_at,
		outcome_at: row.outcome_at,
		...(canViewValue ? { estimated_value: row.estimated_value } : {}),
		client:
			row.client_display_name === null
				? null
				: {
						id: row.client_id,
						display_name: row.client_display_name,
						company_name: row.client_company_name
					}
	}));

	const last = page.at(-1);
	// Which half of a Total sort the next page continues from is read off the last row: a row with no
	// estimate can only have come from the unestimated half, which always comes last.
	const nextCursor =
		hasMore && last
			? encodeOutcomeCursor({
					sort,
					phase: sort === 'total' && last.estimated_value === null ? 2 : 1,
					value:
						sort === 'total'
							? (last.estimated_value?.toString() ?? '')
							: sort === 'title'
								? last.title
								: sort === 'client'
									? (last.client_display_name ?? '')
									: sort === 'created'
										? last.created_at
										: last.outcome_at,
					id: last.id
				})
			: null;

	return json(
		{
			type,
			outcomes,
			next_cursor: nextCursor,
			// The report asks once, here, whether Total and Client are even offerable as sorts, rather than
			// every render guessing from whether a row happens to carry money or a name.
			can_view_value: canViewValue,
			can_view_clients: canViewClients
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
