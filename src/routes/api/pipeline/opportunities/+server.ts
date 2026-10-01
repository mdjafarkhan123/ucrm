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
	sortColumn,
	type BoardCursor,
	type BoardSort
} from '$lib/server/pipeline/board';
import { organizationFormatting } from '$lib/server/requests/timezone';
import { calendarDay } from '$lib/server/time/calendar';
import type { QuoteDeliveryFailureReason } from '$lib/quotes/send';

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
	next_task_due_on: string | null;
	task_id: string | null;
	task_title: string | null;
	task_due_on: string | null;
	quote_id: string | null;
	quote_status: string | null;
	assessment_starts_at: string | null;
	assessment_ends_at: string | null;
	custom_stage_id: string | null;
	quote_delivery_failed_at: string | null;
	quote_delivery_failed_email: string | null;
	quote_delivery_failure: QuoteDeliveryFailureReason | null;
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

	// A marker cut from a different list cannot be paged with — not from a different order, and not from
	// a different column. Replaying one column's cursor against another would page cards that column never
	// showed, and the collapsed Assessment column makes that a real reach rather than a theoretical one.
	// The board sends a fresh request without a cursor whenever the controls change, so this only ever
	// catches a hand-edited URL.
	const cursor = readBoardCursor(parsed.data.cursor);
	if (
		parsed.data.cursor &&
		(!cursor || cursor.column !== stage || cursor.sort !== sort || !cursorFitsItsPhase(cursor))
	) {
		return validationError({ cursor: 'Start this column again.' });
	}

	// A date filter and the Task order both need the organization's calendar: "last month" and "overdue" are
	// questions about the contractor's days, not UTC's. The settings row is held in process, so this is
	// usually no round trip at all.
	let range: { from: string | null; to: string | null } = { from: null, to: null };
	let today: string | null = null;
	if (date !== 'all' || sort === 'attention') {
		const formatting = await organizationFormatting(check.auth.organization.id);
		// A timezone that could not be read is not a reason to answer with the wrong days.
		if (!formatting.ok) return databaseError();
		const { timezone } = formatting.formatting;
		if (date !== 'all') {
			range = resolveDateRange(date, timezone, { from: parsed.data.from, to: parsed.data.to });
		}
		if (sort === 'attention') today = calendarDay(new Date(), timezone);
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
		// Each order's marker goes back as the type its column holds. Money crosses the wire as text so the
		// cursor stays exact. The Task order's middle phase pages by time in the column; its other two by day.
		cursor_timestamp:
			cursor && (cursor.sort === 'stage' || cursor.sort === 'created' || isAttentionTime(cursor))
				? cursor.value
				: undefined,
		cursor_value: cursor && cursor.sort === 'value' ? Number(cursor.value) : undefined,
		cursor_date:
			cursor &&
			(cursor.sort === 'close' || (cursor.sort === 'attention' && !isAttentionTime(cursor)))
				? cursor.value || undefined
				: undefined,
		cursor_id: cursor?.id ?? undefined,
		board_today: today ?? undefined
	});
	if (error) {
		// The one refusal a well-formed request can meet: a custom stage that was switched off after this
		// board was drawn. Said as a field error, so the column can tell a stale board from a failure.
		if (error.code === '22023')
			return validationError({ stage: 'That column is no longer on the board.' });
		return databaseError();
	}

	const returned = (rows ?? []) as BoardPageRow[];
	const page = returned.slice(0, limit);
	const hasMore = returned.length > limit;

	const opportunities = page.map((row) => ({
		id: row.id,
		title: row.title,
		stage: row.stage,
		// The custom follow-up stage somebody placed this card in, or null when it sits in its real stage.
		// `stage` above is the real one either way.
		custom_stage_id: row.custom_stage_id,
		stage_entered_at: row.stage_entered_at,
		outcome: row.outcome,
		created_at: row.created_at,
		expected_close_on: row.expected_close_on,
		// Present only for a member who may see money. Absent, not null, for everyone else.
		...(canViewValue ? { estimated_value: row.estimated_value } : {}),
		request: row.request_id ? { id: row.request_id, status: row.request_status } : null,
		// A quote whose latest email bounced, was refused, or never left says so. The address is already
		// withheld by the database from a member who may not see this client.
		quote: row.quote_id
			? {
					id: row.quote_id,
					status: row.quote_status as string,
					delivery_failure:
						row.quote_delivery_failure && row.quote_delivery_failed_at
							? {
									reason: row.quote_delivery_failure,
									failed_at: row.quote_delivery_failed_at,
									recipient_email: row.quote_delivery_failed_email
								}
							: null
				}
			: null,
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
			: null,
		// The card's one open Task, in the same priority order the Brief's own list uses. Null when the
		// Opportunity has none open.
		task: row.task_id
			? { id: row.task_id, title: row.task_title as string, due_on: row.task_due_on }
			: null,
		// The booked visit, present only once somebody has scheduled one. The collapsed Assessment column
		// shows three sub-states in one place, and "scheduled" is only a useful thing to read on a card if
		// it also says when — the Request status alone cannot answer that.
		assessment: row.assessment_starts_at
			? { starts_at: row.assessment_starts_at, ends_at: row.assessment_ends_at }
			: null
	}));

	const last = page.at(-1);
	const nextCursor =
		hasMore && last ? encodeBoardCursor(cursorAfter(stage, sort, last, today)) : null;

	return json({ stage, opportunities, next_cursor: nextCursor }, { headers: PRIVATE_READ_HEADERS });
};

const ISO_DAY = /^\d{4}-\d{2}-\d{2}$/;

// A marker whose value is not the kind its phase pages by would reach the database as a type error. Only a
// hand-edited URL gets here, so it is simply started again.
function cursorFitsItsPhase(cursor: BoardCursor) {
	switch (cursor.sort) {
		case 'attention':
			return cursor.phase === 2
				? !Number.isNaN(Date.parse(cursor.value))
				: ISO_DAY.test(cursor.value);
		case 'value':
			return cursor.phase !== 3 && (cursor.phase === 2 || Number.isFinite(Number(cursor.value)));
		case 'close':
			return cursor.phase !== 3 && (cursor.phase === 2 || ISO_DAY.test(cursor.value));
		case 'stage':
		case 'created':
			return cursor.phase === 1 && !Number.isNaN(Date.parse(cursor.value));
	}
}

// The Task order's middle phase, cards with no dated Task, pages by when they arrived in the column.
function isAttentionTime(cursor: BoardCursor) {
	return cursor.sort === 'attention' && cursor.phase === 2;
}

// Which phase the next page continues from is read off the last card, because every phase holds only one kind
// of card: an unestimated card can only be from the value sort's second half, a card with no dated Task only
// from the Task order's middle.
function cursorAfter(
	column: string,
	sort: BoardSort,
	last: BoardPageRow,
	today: string | null
): BoardCursor {
	switch (sort) {
		case 'attention': {
			const due = last.next_task_due_on;
			if (due === null)
				return { column, sort, phase: 2, value: last.stage_entered_at, id: last.id };
			return {
				column,
				sort,
				phase: today !== null && due > today ? 3 : 1,
				value: due,
				id: last.id
			};
		}
		case 'value':
			return {
				column,
				sort,
				phase: last.estimated_value === null ? 2 : 1,
				value: last.estimated_value?.toString() ?? '',
				id: last.id
			};
		case 'close':
			return {
				column,
				sort,
				phase: last.expected_close_on === null ? 2 : 1,
				value: last.expected_close_on ?? '',
				id: last.id
			};
		case 'created':
			return { column, sort, phase: 1, value: last.created_at, id: last.id };
		case 'stage':
			return { column, sort, phase: 1, value: last.stage_entered_at, id: last.id };
	}
}
