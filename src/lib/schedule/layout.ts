import type { ScheduleItem } from '$lib/schedule/items';
import { visitShape } from '$lib/schedule/status';

// Where a day's visits sit on a timed grid, and how much of each card fits there.
//
// This is arithmetic, not markup, so it lives here where it can be tested on its own and reused by every
// calendar that draws a time axis. The Week grid places blocks down a day column; the Day board will place
// the same blocks across an employee row from the same numbers.

export const MINUTES_IN_DAY = 24 * 60;

/** How long a visit is drawn when it has a start but no end. A visit is never drawn as a zero-length sliver. */
export const DEFAULT_VISIT_MINUTES = 60;

/** '14:30:00' becomes 870. The stored value is a plain clock time with no timezone in it, so it is read as
 * text rather than put through a Date that would attach one. */
export function clockMinutes(value: string | null): number | null {
	if (!value) return null;
	const [rawHour, rawMinute] = value.split(':');
	const hour = Number(rawHour);
	const minute = Number(rawMinute);
	if (!Number.isFinite(hour) || !Number.isFinite(minute)) return null;
	return Math.max(0, Math.min(MINUTES_IN_DAY, hour * 60 + minute));
}

export type TimedVisitSpan = {
	item: ScheduleItem;
	/** Minutes from midnight. */
	start: number;
	end: number;
};

export type TimedVisitBlock = TimedVisitSpan & {
	/** Which side-by-side lane this block takes, and how many lanes its overlapping group needs. */
	column: number;
	columns: number;
};

export type DayVisitSplit = {
	/** Dated, no clock time. These never get invented a time; they sit in the Anytime lane. */
	anytime: ScheduleItem[];
	timed: TimedVisitSpan[];
};

// An item whose end is missing, or is not after its start, is drawn at the default length rather than being
// hidden or stretched. The stored times are never rewritten -- this only decides what the grid draws.
export function splitDayVisits(items: ScheduleItem[]): DayVisitSplit {
	const anytime: ScheduleItem[] = [];
	const timed: TimedVisitSpan[] = [];

	for (const item of items) {
		const start = visitShape(item) === 'scheduled' ? clockMinutes(item.start_time) : null;
		if (start === null) {
			anytime.push(item);
			continue;
		}
		const rawEnd = clockMinutes(item.end_time);
		const end = rawEnd !== null && rawEnd > start ? rawEnd : start + DEFAULT_VISIT_MINUTES;
		timed.push({ item, start, end: Math.min(MINUTES_IN_DAY, end) });
	}

	return { anytime, timed };
}

// The column-packing every calendar uses: walk the day in start order, keep a group of visits that overlap
// each other, and give each one the first lane that is free at its start time. The group is only as wide as
// the most it ever stacks, so two visits at nine o'clock take half the column each rather than the whole
// day being split into as many lanes as the day has visits.
export function layoutTimedVisits(spans: TimedVisitSpan[]): TimedVisitBlock[] {
	const sorted = [...spans].sort(
		(a, b) => a.start - b.start || b.end - a.end || a.item.id.localeCompare(b.item.id)
	);

	const blocks: TimedVisitBlock[] = [];
	let group: TimedVisitBlock[] = [];
	let groupEnd = -1;
	// The last minute each lane is busy until, for the group being built.
	let laneEnds: number[] = [];

	function closeGroup() {
		for (const block of group) block.columns = laneEnds.length;
		blocks.push(...group);
		group = [];
		laneEnds = [];
		groupEnd = -1;
	}

	for (const span of sorted) {
		// Nothing in the group is still running, so this visit starts a fresh one.
		if (group.length > 0 && span.start >= groupEnd) closeGroup();

		let lane = laneEnds.findIndex((end) => end <= span.start);
		if (lane === -1) lane = laneEnds.length;
		laneEnds[lane] = span.end;

		group.push({ ...span, column: lane, columns: laneEnds.length });
		groupEnd = Math.max(groupEnd, span.end);
	}
	if (group.length > 0) closeGroup();

	return blocks;
}

export type CardDensity = 'micro' | 'compact' | 'standard';

// How much of a card fits in the space the grid gave it. A short visit keeps its true duration and drops to
// the smallest form rather than being grown to fit its own text, and a visit sharing its hour with others
// gives up detail before it gives up being readable.
export function cardDensity(heightPx: number, columns: number): CardDensity {
	if (heightPx < 34 || columns > 3) return 'micro';
	if (heightPx < 64 || columns > 1) return 'compact';
	return 'standard';
}

// The same question asked sideways. On the Day board a row hands every card the same height and duration
// decides its width instead, so a half-hour visit is a narrow sliver however tall its lane is. Overlaps do
// not enter into it there: they stack down the row rather than splitting the width.
export function cardDensityForWidth(widthPx: number): CardDensity {
	if (widthPx < 104) return 'micro';
	if (widthPx < 208) return 'compact';
	return 'standard';
}
