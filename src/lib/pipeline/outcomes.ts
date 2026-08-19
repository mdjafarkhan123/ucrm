// The Sales Outcomes report's own controls, in the one place both the browser and the server read them --
// the same split `$lib/pipeline/filters` draws for the board. Won and Lost are never mixed on one page, so
// `type` is not optional the way the board's owner filter is.
//
// The date preset vocabulary is the board's own (`BOARD_DATE_PRESETS`): it is a generic "which days" list,
// not board-specific knowledge, and the report applies it to Outcome date instead of Created date.

import { BOARD_DATE_PRESETS, BOARD_DATE_LABELS, type BoardDatePreset } from '$lib/pipeline/filters';

export { BOARD_DATE_PRESETS as OUTCOME_DATE_PRESETS, BOARD_DATE_LABELS as OUTCOME_DATE_LABELS };
export type OutcomeDatePreset = BoardDatePreset;

export const OUTCOME_TYPES = ['won', 'lost'] as const;
export type OutcomeType = (typeof OUTCOME_TYPES)[number];

export const OUTCOME_TYPE_LABELS: Record<OutcomeType, string> = {
	won: 'Won',
	lost: 'Lost'
};

export const OUTCOME_SORTS = ['title', 'client', 'created', 'outcome_at', 'total'] as const;
export type OutcomeSort = (typeof OUTCOME_SORTS)[number];

export const OUTCOME_SORT_LABELS: Record<OutcomeSort, string> = {
	title: 'Title',
	client: 'Client',
	created: 'Created At',
	outcome_at: 'Outcome date',
	total: 'Total'
};

export const OUTCOME_DIRECTIONS = ['asc', 'desc'] as const;
export type OutcomeDirection = (typeof OUTCOME_DIRECTIONS)[number];

export type OutcomeFilters = {
	type: OutcomeType;
	sort: OutcomeSort;
	direction: OutcomeDirection;
	date: OutcomeDatePreset;
	// Only ever set while `date` is `custom`, and at least one end is needed before the range means anything.
	from?: string;
	to?: string;
};

// What the report asks for from a bare `/pipeline/outcomes` visit. Won, because that is Jobber's own
// default -- Won showing an empty state until Quotes and automatic Won exist is honest, not a reason to
// design the default around a gap that will close.
export const DEFAULT_OUTCOME_FILTERS: OutcomeFilters = {
	type: 'won',
	sort: 'outcome_at',
	direction: 'desc',
	date: 'all'
};

export function outcomeFiltersAreComplete(filters: OutcomeFilters) {
	return filters.date !== 'custom' || Boolean(filters.from) || Boolean(filters.to);
}

export function outcomeFiltersAreDefault(filters: OutcomeFilters) {
	return (
		filters.type === DEFAULT_OUTCOME_FILTERS.type &&
		filters.sort === DEFAULT_OUTCOME_FILTERS.sort &&
		filters.direction === DEFAULT_OUTCOME_FILTERS.direction &&
		filters.date === DEFAULT_OUTCOME_FILTERS.date
	);
}

const ISO_DAY = /^\d{4}-\d{2}-\d{2}$/;

// The URL is the report's memory and its untrusted input alike: a hand-edited or stale link falls back to
// the default for whatever it got wrong rather than putting an error on screen.
export function readOutcomeFilters(params: URLSearchParams): OutcomeFilters {
	const one = <Value extends string>(
		key: string,
		allowed: readonly Value[],
		fallback: Value
	): Value => {
		const raw = params.get(key);
		return raw && (allowed as readonly string[]).includes(raw) ? (raw as Value) : fallback;
	};

	const date = one('date', BOARD_DATE_PRESETS, 'all');
	const day = (key: string) => {
		const raw = params.get(key);
		return raw && ISO_DAY.test(raw) ? raw : undefined;
	};

	return {
		type: one('type', OUTCOME_TYPES, DEFAULT_OUTCOME_FILTERS.type),
		sort: one('sort', OUTCOME_SORTS, DEFAULT_OUTCOME_FILTERS.sort),
		direction: one('direction', OUTCOME_DIRECTIONS, DEFAULT_OUTCOME_FILTERS.direction),
		date,
		...(date === 'custom' ? { from: day('from'), to: day('to') } : {})
	};
}

// What goes in the URL, and what goes in the request. Anything still at its default is left out, so a tile
// link only ever carries `type` and `date` and the report's own address stays readable.
export function outcomeFilterParams(filters: OutcomeFilters): URLSearchParams {
	const params = new URLSearchParams();
	if (filters.type !== DEFAULT_OUTCOME_FILTERS.type) params.set('type', filters.type);
	if (filters.sort !== DEFAULT_OUTCOME_FILTERS.sort) params.set('sort', filters.sort);
	if (filters.direction !== DEFAULT_OUTCOME_FILTERS.direction)
		params.set('direction', filters.direction);
	if (filters.date !== DEFAULT_OUTCOME_FILTERS.date) params.set('date', filters.date);
	if (filters.date === 'custom') {
		if (filters.from) params.set('from', filters.from);
		if (filters.to) params.set('to', filters.to);
	}
	return params;
}

export function outcomeFilterKey(filters: OutcomeFilters): string {
	const params = outcomeFilterParams(filters);
	params.sort();
	return params.toString();
}
