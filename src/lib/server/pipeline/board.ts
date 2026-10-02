import { calendarParts, calendarWeekday, localMidnight } from '$lib/server/time/calendar';
import {
	BOARD_SORTS,
	BOARD_DIRECTIONS,
	BOARD_DATE_PRESETS,
	type BoardSort,
	type BoardDirection,
	type BoardDatePreset
} from '$lib/pipeline/filters';
import { TABLE_SCOPE, isBoardColumnKey, isCustomStageId } from '$lib/pipeline/stages';

// The board's controls, translated from what a URL can carry into what the database read expects.
//
// Two translations live here. The cursor has to remember which order it was cut from, because a page
// marker from one sort means nothing in another. And the date presets have to become two instants,
// because "last month" is a question about the contractor's calendar, not about UTC, and the calendar
// rule already exists in one place on the server.

// The names themselves are the URL's vocabulary, not server knowledge, so they live in `$lib/pipeline/filters`
// where the control bar can read them too. Re-exported here so the routes and the schema keep one import.
export {
	BOARD_SORTS,
	BOARD_DIRECTIONS,
	BOARD_DATE_PRESETS,
	type BoardSort,
	type BoardDirection,
	type BoardDatePreset
};

// What the sort is called in the URL, and what the column it orders by is called in the database.
const SORT_COLUMNS: Record<
	BoardSort,
	'attention' | 'stage_entered_at' | 'created_at' | 'estimated_value' | 'expected_close_on'
> = {
	attention: 'attention',
	stage: 'stage_entered_at',
	created: 'created_at',
	value: 'estimated_value',
	close: 'expected_close_on'
};

export function sortColumn(sort: BoardSort) {
	return SORT_COLUMNS[sort];
}

// The search box and the lead source, as the two board functions take them. Both routes build them here,
// so the cards and the headings above them are always asked the same question.
//
// One typed term is matched three ways. As text, anywhere in a title, a name, an address, an email, or a
// phone number as it was typed. As digits, when the term reads as a phone number, against the stored
// digits-only form, so "(555) 010-2030" finds "555-010-2030". And as a Quote number, when it reads as one.
export type BoardRecordFilters = {
	search_like?: string;
	search_digits?: string;
	search_number?: number;
	lead_source_filter?: string;
};

const PHONE_SHAPED = /^[\d\s()+.-]+$/;
const NUMBER_SHAPED = /^#?(\d{1,9})$/;

export function recordFilters(
	q: string | undefined,
	source: string | undefined
): BoardRecordFilters {
	const filters: BoardRecordFilters = {};
	if (source) filters.lead_source_filter = source;
	if (!q) return filters;

	// The term's own wildcards are escaped, so a search for "50%" looks for those three characters.
	filters.search_like = `%${q.replace(/[\\%_]/g, (character) => `\\${character}`)}%`;

	if (PHONE_SHAPED.test(q)) {
		const digits = q.replace(/\D/g, '');
		if (digits.length >= 3 && digits.length <= 20) filters.search_digits = digits;
	}
	const number = NUMBER_SHAPED.exec(q);
	if (number) filters.search_number = Number(number[1]);

	return filters;
}

// A cursor is "<column>:<sort>:<phase>:<the sort column's value>|<id>". Both the column and the sort are
// in it, because a marker means nothing outside the list it was cut from: replayed against another order
// it would skip and repeat cards, and replayed against another column it would page a set of cards that
// column never showed. The phase matters for three sorts. By value or expected close, 1 is the cards that have
// one and 2 is those that do not, which always come after. In the Task order, 1 is a Task due today or
// earlier, 2 is no dated Task, and 3 is a Task due later.
export type BoardCursor = {
	// A protected column's name, a custom stage's id, or the Table view's whole-board scope.
	column: string;
	sort: BoardSort;
	phase: 1 | 2 | 3;
	value: string;
	id: string;
};

export function encodeBoardCursor(cursor: BoardCursor) {
	return `${cursor.column}:${cursor.sort}:${cursor.phase}:${cursor.value}|${cursor.id}`;
}

export function readBoardCursor(raw: string | null | undefined): BoardCursor | null {
	if (!raw) return null;
	const separator = raw.lastIndexOf('|');
	if (separator < 1) return null;
	const id = raw.slice(separator + 1);
	if (id.length === 0) return null;

	// Only the three head fields are split off. The value keeps every remaining colon, because an ISO
	// instant is full of them.
	const head = raw.slice(0, separator);
	const firstColon = head.indexOf(':');
	const secondColon = head.indexOf(':', firstColon + 1);
	const thirdColon = head.indexOf(':', secondColon + 1);
	if (firstColon < 1 || secondColon < 0 || thirdColon < 0) return null;

	const column = head.slice(0, firstColon);
	if (column !== TABLE_SCOPE && !isBoardColumnKey(column) && !isCustomStageId(column)) return null;
	const sort = head.slice(firstColon + 1, secondColon) as BoardSort;
	if (!(BOARD_SORTS as readonly string[]).includes(sort)) return null;
	const phase = Number(head.slice(secondColon + 1, thirdColon));
	if (phase !== 1 && phase !== 2 && phase !== 3) return null;

	return { column, sort, phase, value: head.slice(thirdColon + 1), id };
}

// Every preset ends up as a half-open range: from the first moment of its first day, up to but not
// including the first moment of the day after it ends. Null on either side means unbounded.
//
// "Last week" and "Last month" mean the previous whole week and the previous whole month, the way a
// contractor reads them on a calendar. "Last 30 days" and "Last 12 months" are rolling and include
// today. Weeks start on Sunday, which is the week the schedule already uses.
export type BoardDateRange = { from: string | null; to: string | null };

export function resolveDateRange(
	preset: BoardDatePreset,
	timezone: string,
	custom?: { from?: string; to?: string },
	now: Date = new Date()
): BoardDateRange {
	const today = calendarParts(now, timezone);
	const at = (year: number, month: number, day: number) =>
		localMidnight(year, month, day, timezone, now).toISOString();
	const startOfTomorrow = () => at(today.year, today.month, today.day + 1);

	switch (preset) {
		case 'all':
			return { from: null, to: null };

		case 'last_week': {
			// Back to this week's Sunday, then back one more week.
			const thisWeekStart = today.day - calendarWeekday(now, timezone);
			return {
				from: at(today.year, today.month, thisWeekStart - 7),
				to: at(today.year, today.month, thisWeekStart)
			};
		}

		case 'last_30_days':
			// Thirty days including today, so twenty-nine days back plus the whole of today.
			return { from: at(today.year, today.month, today.day - 29), to: startOfTomorrow() };

		case 'last_month':
			return { from: at(today.year, today.month - 1, 1), to: at(today.year, today.month, 1) };

		case 'this_month':
			return { from: at(today.year, today.month, 1), to: startOfTomorrow() };

		case 'this_year':
			return { from: at(today.year, 1, 1), to: startOfTomorrow() };

		case 'last_12_months':
			// From the same date a year ago, through today. Both ends included, the way somebody reading
			// "the last 12 months" on a calendar counts them.
			return { from: at(today.year - 1, today.month, today.day), to: startOfTomorrow() };

		case 'custom': {
			// Both ends are optional, so "everything since March" and "everything up to March" are both
			// sayable. The end day is included, which is what picking it on a calendar means.
			const from = readDay(custom?.from);
			const to = readDay(custom?.to);
			return {
				from: from ? at(from.year, from.month, from.day) : null,
				to: to ? at(to.year, to.month, to.day + 1) : null
			};
		}
	}
}

function readDay(value: string | undefined) {
	if (!value) return null;
	const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
	if (!match) return null;
	return { year: Number(match[1]), month: Number(match[2]), day: Number(match[3]) };
}
