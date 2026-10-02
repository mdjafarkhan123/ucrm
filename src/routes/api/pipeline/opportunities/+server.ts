import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { boardQuerySchema } from '$lib/server/validation/pipeline.schema';
import {
	encodeBoardCursor,
	readBoardCursor,
	recordFilters,
	resolveDateRange,
	sortColumn,
	type BoardCursor,
	type BoardSort
} from '$lib/server/pipeline/board';
import { organizationFormatting } from '$lib/server/requests/timezone';
import { calendarDay } from '$lib/server/time/calendar';
import { toBoardCard, type BoardPageRow } from '$lib/server/pipeline/card';

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
		to: query.get('to') ?? undefined,
		q: query.get('q') ?? undefined,
		source: query.get('source') ?? undefined
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
		board_today: today ?? undefined,
		...recordFilters(parsed.data.q, parsed.data.source)
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

	const opportunities = page.map((row) => toBoardCard(row, canViewValue));

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
