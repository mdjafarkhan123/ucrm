import { OUTCOME_SORTS, type OutcomeSort } from '$lib/pipeline/outcomes';

// A cursor is "<sort>:<phase>:<the sort column's value>|<id>", the same shape the board's own cursor uses
// and for the same reason: the sort is in it so a marker cut from one order is refused rather than quietly
// paging the wrong list. The phase only matters for `total` -- 1 is the estimated rows, 2 is the
// unestimated ones that always come after them.
export type OutcomeCursor = {
	sort: OutcomeSort;
	phase: 1 | 2;
	value: string;
	id: string;
};

export function encodeOutcomeCursor(cursor: OutcomeCursor) {
	return `${cursor.sort}:${cursor.phase}:${cursor.value}|${cursor.id}`;
}

export function readOutcomeCursor(raw: string | null | undefined): OutcomeCursor | null {
	if (!raw) return null;
	const separator = raw.lastIndexOf('|');
	if (separator < 1) return null;
	const id = raw.slice(separator + 1);
	if (id.length === 0) return null;

	const head = raw.slice(0, separator);
	const firstColon = head.indexOf(':');
	const secondColon = head.indexOf(':', firstColon + 1);
	if (firstColon < 1 || secondColon < 0) return null;

	const sort = head.slice(0, firstColon) as OutcomeSort;
	if (!(OUTCOME_SORTS as readonly string[]).includes(sort)) return null;
	const phase = Number(head.slice(firstColon + 1, secondColon));
	if (phase !== 1 && phase !== 2) return null;

	return { sort, phase, value: head.slice(secondColon + 1), id };
}
