// The board's controls, in the one place both sides can read them.
//
// The names of the sorts, the directions and the date presets used to live in `$lib/server/pipeline/board.ts`,
// which the browser may not import. They are not server knowledge — they are the vocabulary of the URL, and
// the control bar, the query keys and the two API routes all have to agree on it exactly or a filtered board
// quietly answers about a different set of cards than it is showing. So they live here, and the server module
// reads them from here.

// `attention` is the Task order: overdue Task, due today, no Task, then a Task due later. It is a work queue,
// so it has no direction.
export const BOARD_SORTS = ['attention', 'stage', 'created', 'value', 'close'] as const;
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
	// What was typed in the search box, trimmed. Absent until it is long enough to search with.
	q?: string;
	// One lead source, exactly as the client record spells it. Absent means every source.
	source?: string;
};

// A search needs two characters before it narrows anything, the same floor the top-bar search uses.
export const BOARD_SEARCH_MIN = 2;
export const BOARD_SEARCH_MAX = 100;
// The longest lead source a client record can hold.
export const BOARD_LEAD_SOURCE_MAX = 80;

// The search box holds whatever is being typed; this is the part of it the board will act on.
export function searchTerm(raw: string | null | undefined): string | undefined {
	const term = raw?.trim() ?? '';
	return term.length >= BOARD_SEARCH_MIN && term.length <= BOARD_SEARCH_MAX ? term : undefined;
}

// What an untouched board asks for: the Task order, everybody, all time. Kept in one place so the
// URL can leave out anything still at its default and stay readable.
export const DEFAULT_BOARD_FILTERS: BoardFilters = {
	sort: 'attention',
	direction: 'desc',
	owner: 'all',
	date: 'all'
};

export const BOARD_SORT_LABELS: Record<BoardSort, string> = {
	attention: 'Next Task',
	stage: 'Time in stage',
	created: 'Created date',
	value: 'Value',
	close: 'Expected close'
};

// Whether the arrow beside the sort means anything. The Task order is a fixed queue.
export function sortHasDirection(sort: BoardSort) {
	return sort !== 'attention';
}

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
	if (sort === 'close') return direction === 'desc' ? 'Latest first' : 'Soonest first';
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
		filters.date === DEFAULT_BOARD_FILTERS.date &&
		!filters.q &&
		!filters.source
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

	const q = searchTerm(params.get('q'));
	const rawSource = params.get('source')?.trim() ?? '';
	const source =
		rawSource.length > 0 && rawSource.length <= BOARD_LEAD_SOURCE_MAX ? rawSource : undefined;

	return {
		sort: one('sort', BOARD_SORTS, DEFAULT_BOARD_FILTERS.sort),
		direction: one('direction', BOARD_DIRECTIONS, DEFAULT_BOARD_FILTERS.direction),
		owner,
		date,
		// The two ends only mean anything inside a custom range; carrying them any other time would put
		// them in the query key and split the cache for no reason.
		...(date === 'custom' ? { from: day('from'), to: day('to') } : {}),
		// Left out entirely when unset, for the same reason: an `undefined` key is still a key.
		...(q ? { q } : {}),
		...(source ? { source } : {})
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
	if (filters.q) params.set('q', filters.q);
	if (filters.source) params.set('source', filters.source);
	return params;
}

// What a saved filter keeps: every control except the search box, as one stable string. A filter is a
// standing view ("my Google leads, oldest first"), not a one-off lookup, so a search typed on top of it
// still leaves the board on that filter. Empty means the controls are all at their defaults — nothing to save.
export const SAVED_FILTER_NAME_MAX = 60;

export function savedFilterQuery(filters: BoardFilters): string {
	const params = boardFilterParams({ ...filters, q: undefined });
	params.sort();
	return params.toString();
}

// The board as a saved filter would leave it: that filter's controls, the search box cleared.
export function filtersFromSavedQuery(query: string): BoardFilters {
	const filters = readBoardFilters(new URLSearchParams(query));
	delete filters.q;
	return filters;
}

// The same filters as one stable string, for the query keys. Sorted, so two identical filter sets that were
// built in a different order are still the same cache entry.
export function boardFilterKey(filters: BoardFilters): string {
	const params = boardFilterParams(filters);
	params.sort();
	return params.toString();
}
