import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { boardQuerySchema } from '$lib/server/validation/pipeline.schema';
import {
	encodeBoardCursor,
	readBoardCursor,
	resolveDateRange,
	sortColumn
} from '$lib/server/pipeline/board';
import { organizationFormatting } from '$lib/server/requests/timezone';

// `locals.supabase` is an untyped client, and the generated types for a returns-table function claim
// every column is non-null, which is wrong for this one by design: hidden client details, an unassigned
// owner, and money the caller may not see all come back null. So the row is described here, honestly.
type BoardPageRow = {
	id: string;
	title: string;
	stage: string;
	stage_entered_at: string;
	outcome: string;
	created_at: string;
	request_id: string | null;
	request_status: string | null;
	client_id: string;
	client_display_name: string | null;
	client_company_name: string | null;
	property_id: string | null;
	property_label: string | null;
	property_address_line1: string | null;
	property_city: string | null;
	property_state_region: string | null;
	property_postal_code: string | null;
	owner_user_id: string | null;
	owner_full_name: string | null;
	owner_avatar_url: string | null;
	estimated_value: number | null;
	expected_close_on: string | null;
	next_follow_up_on: string | null;
};

// One board column at a time. Each column asks for its own page, so a busy stage can keep loading
// without making the other three fetch again. Read only: an Opportunity is created by the Request
// trigger and by nothing else, so this route has no write path.
//
// The read goes through `pipeline_board_page` rather than a select, because members hold no privilege
// on the value column at all. That function re-applies every rule it runs past — tenant, pipeline
// access, client visibility, and whether this member may see money — so this route's job is to shape
// the answer, not to guard it. Money is guarded twice all the same: the field is left out of the
// payload entirely for a member without it, so there is nothing to leak and nothing to misread.
//
// The sort, the salesperson and the date range are the board's controls. The route turns the date
// preset into two instants in the organization's own timezone, because "last month" is a question about
// the contractor's calendar; the database only ever sees the answer.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;

	const query = event.url.searchParams;
	const parsed = boardQuerySchema.safeParse({
		stage: query.get('stage') ?? undefined,
		cursor: query.get('cursor') ?? undefined,
		limit: query.get('limit') ?? undefined,
		sort: query.get('sort') ?? undefined,
		direction: query.get('direction') ?? undefined,
		owner: query.get('owner') ?? undefined,
		date: query.get('date') ?? undefined,
		from: query.get('from') ?? undefined,
		to: query.get('to') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { stage, limit, sort, direction, owner, date } = parsed.data;
	const canViewValue = hasPermission(check.access, 'pipeline.view_value');

	// Sorting by value is reading value. Refused here as well as in the database, so a member without
	// money never learns the ranking through an error they could time.
	if (sort === 'value' && !canViewValue) {
		return json({ error: 'You cannot sort this board by value.' }, { status: 403 });
	}

	// A marker cut from a different order cannot be paged with. The board sends a fresh request without
	// one whenever the controls change, so this only ever catches a hand-edited URL.
	const cursor = readBoardCursor(parsed.data.cursor);
	const cursorValueIsBroken =
		cursor?.sort === 'value' && cursor.phase === 1 && !Number.isFinite(Number(cursor.value));
	if (parsed.data.cursor && (!cursor || cursor.sort !== sort || cursorValueIsBroken)) {
		return validationError({ cursor: 'Start this column again.' });
	}

	// Only a real date filter needs the organization's calendar, so an unfiltered board still costs one
	// database round trip.
	let range: { from: string | null; to: string | null } = { from: null, to: null };
	if (date !== 'all') {
		const formatting = await organizationFormatting(
			event.locals.supabase,
			check.auth.organization.id
		);
		// A timezone that could not be read is not a reason to answer with the wrong days.
		if (!formatting.ok) return databaseError();
		range = resolveDateRange(date, formatting.formatting.timezone, {
			from: parsed.data.from,
			to: parsed.data.to
		});
	}

	// One extra row answers "is there more" without a second count query.
	const { data: rows, error } = await event.locals.supabase.rpc('pipeline_board_page', {
		target_organization_id: check.auth.organization.id,
		target_stage: stage,
		page_limit: limit + 1,
		sort_key: sortColumn(sort),
		sort_direction: direction,
		owner_filter: owner === 'all' || owner === 'unassigned' ? owner : 'member',
		filter_owner_user_id: owner === 'all' || owner === 'unassigned' ? undefined : owner,
		created_from: range.from ?? undefined,
		created_to: range.to ?? undefined,
		cursor_sort_key: cursor ? sortColumn(cursor.sort) : undefined,
		cursor_phase: cursor?.phase ?? undefined,
		cursor_timestamp: cursor && cursor.sort !== 'value' ? cursor.value : undefined,
		// Money crosses the wire as text so the cursor stays exact, and goes back to the database as the
		// number the column actually holds.
		cursor_value: cursor && cursor.sort === 'value' ? Number(cursor.value) : undefined,
		cursor_id: cursor?.id ?? undefined
	});
	if (error) return databaseError();

	const returned = (rows ?? []) as BoardPageRow[];
	const page = returned.slice(0, limit);
	const hasMore = returned.length > limit;

	const opportunities = page.map((row) => ({
		id: row.id,
		title: row.title,
		stage: row.stage,
		stage_entered_at: row.stage_entered_at,
		outcome: row.outcome,
		created_at: row.created_at,
		expected_close_on: row.expected_close_on,
		next_follow_up_on: row.next_follow_up_on,
		// Present only for a member who may see money. Absent, not null, for everyone else.
		...(canViewValue ? { estimated_value: row.estimated_value } : {}),
		request: row.request_id ? { id: row.request_id, status: row.request_status } : null,
		// A member who may not see this client gets the card without the client's details, exactly as
		// the clients table would have answered.
		client:
			row.client_display_name === null
				? null
				: {
						id: row.client_id,
						display_name: row.client_display_name,
						company_name: row.client_company_name
					},
		property:
			row.property_id === null || row.property_address_line1 === null
				? null
				: {
						id: row.property_id,
						label: row.property_label,
						address_line1: row.property_address_line1,
						city: row.property_city,
						state_region: row.property_state_region,
						postal_code: row.property_postal_code
					},
		// The name is missing when the owner has left the team; the ownership itself is kept.
		owner: row.owner_user_id
			? {
					id: row.owner_user_id,
					full_name: row.owner_full_name,
					avatar_url: row.owner_avatar_url
				}
			: null
	}));

	const last = page.at(-1);
	// Which half of a value sort the next page continues from is read off the last card: a card with no
	// estimate can only have come from the unestimated half, which always comes last.
	const nextCursor =
		hasMore && last
			? encodeBoardCursor({
					sort,
					phase: sort === 'value' && last.estimated_value === null ? 2 : 1,
					value:
						sort === 'value'
							? (last.estimated_value?.toString() ?? '')
							: sort === 'created'
								? last.created_at
								: last.stage_entered_at,
					id: last.id
				})
			: null;

	return json({ stage, opportunities, next_cursor: nextCursor }, { headers: PRIVATE_READ_HEADERS });
};
