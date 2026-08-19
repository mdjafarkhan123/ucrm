// The board's controls, in the one place both sides can read them.
//
// The names of the sorts, the directions and the date presets used to live in `$lib/server/pipeline/board.ts`,
// which the browser may not import. They are not server knowledge — they are the vocabulary of the URL, and
// the control bar, the query keys and the two API routes all have to agree on it exactly or a filtered board
// quietly answers about a different set of cards than it is showing. So they live here, and the server module
// reads them from here.

export const BOARD_SORTS = ['stage', 'created', 'value'] as const;
export type BoardSort = (typeof BOARD_SORTS)[number];

export const BOARD_DIRECTIONS = ['asc', 'desc'] as const;
export type BoardDirection = (typeof BOARD_DIRECTIONS)[number];

export const BOARD_DATE_PRESETS = [
	'all',
	'last_week',
	'last_30_days',
	'last_month',
	'this_month',
	'this_year',
	'last_12_months',
	'custom'
] as const;
export type BoardDatePreset = (typeof BOARD_DATE_PRESETS)[number];

// One salesperson, everybody, or nobody. One value rather than a filter and a flag that can disagree.
export type BoardOwnerFilter = 'all' | 'unassigned' | (string & {});

export type BoardFilters = {
	sort: BoardSort;
	direction: BoardDirection;
	owner: BoardOwnerFilter;
	date: BoardDatePreset;
	// Only ever set while `date` is `custom`, and at least one end is needed before the range means anything.
	from?: string;
	to?: string;
};

// What an untouched board asks for: newest stage entry first, everybody, all time. Kept in one place so the
// URL can leave out anything still at its default and stay readable.
export const DEFAULT_BOARD_FILTERS: BoardFilters = {
	sort: 'stage',
	direction: 'desc',
	owner: 'all',
	date: 'all'
};

export const BOARD_SORT_LABELS: Record<BoardSort, string> = {
	stage: 'Time in stage',
	created: 'Created date',
	value: 'Value'
};

export const BOARD_DATE_LABELS: Record<BoardDatePreset, string> = {
	all: 'All',
	last_week: 'Last week',
	last_30_days: 'Last 30 days',
	last_month: 'Last month',
	this_month: 'This month',
	this_year: 'This year',
	last_12_months: 'Last 12 months',
	custom: 'Custom range'
};

// Which way round the arrow reads depends on what is being ordered. "Newest first" means nothing about money,
// and "highest first" means nothing about a date, so the button says the right thing for the sort it is next to.
export function directionLabel(sort: BoardSort, direction: BoardDirection) {
	if (sort === 'value') return direction === 'desc' ? 'Highest first' : 'Lowest first';
	return direction === 'desc' ? 'Newest first' : 'Oldest first';
}

// A custom range needs at least one end before it is a question the API will answer. Until then the board
// keeps showing what it was showing, rather than firing a request that comes back as a validation error.
export function filtersAreComplete(filters: BoardFilters) {
	return filters.date !== 'custom' || Boolean(filters.from) || Boolean(filters.to);
}

export function filtersAreDefault(filters: BoardFilters) {
	return (
		filters.sort === DEFAULT_BOARD_FILTERS.sort &&
		filters.direction === DEFAULT_BOARD_FILTERS.direction &&
		filters.owner === DEFAULT_BOARD_FILTERS.owner &&
		filters.date === DEFAULT_BOARD_FILTERS.date
	);
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ISO_DAY = /^\d{4}-\d{2}-\d{2}$/;

// The URL is the board's memory, so it is also the board's untrusted input: a hand-edited or stale link falls
// back to the default for whatever it got wrong rather than putting an error on screen.
export function readBoardFilters(params: URLSearchParams): BoardFilters {
	const one = <Value extends string>(
		key: string,
		allowed: readonly Value[],
		fallback: Value
	): Value => {
		const raw = params.get(key);
		return raw && (allowed as readonly string[]).includes(raw) ? (raw as Value) : fallback;
	};

	const rawOwner = params.get('owner');
	const owner: BoardOwnerFilter =
		rawOwner === 'unassigned' || (rawOwner && UUID.test(rawOwner)) ? rawOwner : 'all';

	const date = one('date', BOARD_DATE_PRESETS, 'all');
	const day = (key: string) => {
		const raw = params.get(key);
		return raw && ISO_DAY.test(raw) ? raw : undefined;
	};

	return {
		sort: one('sort', BOARD_SORTS, DEFAULT_BOARD_FILTERS.sort),
		direction: one('direction', BOARD_DIRECTIONS, DEFAULT_BOARD_FILTERS.direction),
		owner,
		date,
		// The two ends only mean anything inside a custom range; carrying them any other time would put
		// them in the query key and split the cache for no reason.
		...(date === 'custom' ? { from: day('from'), to: day('to') } : {})
	};
}

// What goes in the URL, and what goes in the request. Anything still at its default is left out, so an
// untouched board keeps a clean address and every filtered one describes itself completely.
export function boardFilterParams(filters: BoardFilters): URLSearchParams {
	const params = new URLSearchParams();
	if (filters.sort !== DEFAULT_BOARD_FILTERS.sort) params.set('sort', filters.sort);
	if (filters.direction !== DEFAULT_BOARD_FILTERS.direction)
		params.set('direction', filters.direction);
	if (filters.owner !== DEFAULT_BOARD_FILTERS.owner) params.set('owner', filters.owner);
	if (filters.date !== DEFAULT_BOARD_FILTERS.date) params.set('date', filters.date);
	if (filters.date === 'custom') {
		if (filters.from) params.set('from', filters.from);
		if (filters.to) params.set('to', filters.to);
	}
	return params;
}

// The same filters as one stable string, for the query keys. Sorted, so two identical filter sets that were
// built in a different order are still the same cache entry.
export function boardFilterKey(filters: BoardFilters): string {
	const params = boardFilterParams(filters);
	params.sort();
	return params.toString();
}
