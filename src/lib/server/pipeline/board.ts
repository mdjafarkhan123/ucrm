import { calendarParts, calendarWeekday, localMidnight } from '$lib/server/time/calendar';
import {
	BOARD_SORTS,
	BOARD_DIRECTIONS,
	BOARD_DATE_PRESETS,
	type BoardSort,
	type BoardDirection,
	type BoardDatePreset
} from '$lib/pipeline/filters';
import { isBoardColumnKey, type BoardColumnKey } from '$lib/pipeline/stages';

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
const SORT_COLUMNS: Record<BoardSort, 'stage_entered_at' | 'created_at' | 'estimated_value'> = {
	stage: 'stage_entered_at',
	created: 'created_at',
	value: 'estimated_value'
};

export function sortColumn(sort: BoardSort) {
	return SORT_COLUMNS[sort];
}

// A cursor is "<column>:<sort>:<phase>:<the sort column's value>|<id>". Both the column and the sort are
// in it, because a marker means nothing outside the list it was cut from: replayed against another order
// it would skip and repeat cards, and replayed against another column it would page a set of cards that
// column never showed. The phase only matters when sorting by value: 1 is the estimated cards, 2 is the
// unestimated ones that always come after them.
export type BoardCursor = {
	column: BoardColumnKey;
	sort: BoardSort;
	phase: 1 | 2;
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
	if (!isBoardColumnKey(column)) return null;
	const sort = head.slice(firstColon + 1, secondColon) as BoardSort;
	if (!(BOARD_SORTS as readonly string[]).includes(sort)) return null;
	const phase = Number(head.slice(secondColon + 1, thirdColon));
	if (phase !== 1 && phase !== 2) return null;

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
