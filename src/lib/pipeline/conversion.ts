// The Sales Outcomes conversion report: what became of the work that came in during a period. The
// database returns raw counts for work grouped by the day it was created; the rates are divided here, in
// one place, so the route, the page and the tests cannot disagree about what a percentage means.
//
// The rule every rate follows (Pipedrive's win/loss conversion): only work that is no longer open is
// divided. Open work is shown beside the rate, never inside it, so a month still in progress does not
// read as a month of losses.

import {
	BOARD_STAGES,
	QUOTE_BOARD_STAGES,
	ALL_STAGE_LABELS,
	type AnyBoardStage
} from '$lib/pipeline/stages';

// One Request and its Quote are one piece of work. `closed` ended with no result at all: archived without
// being marked Lost, or converted to a Quote that was abandoned before sending.
export type WorkCounts = {
	total: number;
	won: number;
	lost: number;
	closed: number;
	open: number;
};

export type RequestCounts = WorkCounts & {
	/** Requests that got a Quote that was not abandoned before sending. */
	quoted: number;
	/** Still open and not yet quoted: these may still become a Quote. */
	open_unquoted: number;
};

export type QuoteCounts = {
	total: number;
	won: number;
	lost: number;
	open: number;
	/** Draft Quotes archived before anybody saw them. Never a win or a loss. */
	abandoned: number;
};

export type Rate = {
	/** Whole percent, or null when nothing has been decided yet. Never a fake 0%. */
	percent: number | null;
	hits: number;
	outOf: number;
};

export function rate(hits: number, outOf: number): Rate {
	return { percent: outOf > 0 ? Math.round((hits / outOf) * 100) : null, hits, outOf };
}

// The three figures the plan keeps apart.
export function requestToQuoteRate(requests: RequestCounts): Rate {
	return rate(requests.quoted, requests.total - requests.open_unquoted);
}
export function requestToWonRate(requests: RequestCounts): Rate {
	return rate(requests.won, requests.total - requests.open);
}
export function quoteWinRate(quotes: QuoteCounts): Rate {
	return rate(quotes.won, quotes.won + quotes.lost);
}
export function workWinRate(work: WorkCounts): Rate {
	return rate(work.won, work.total - work.open);
}

export function formatRate(value: Rate) {
	return value.percent === null ? '—' : `${value.percent}%`;
}

// Tenths of a day are noise next to days, and a stage cards pass straight through should not read "0".
export function formatDays(value: number) {
	if (value < 0.1) return 'Under 1 hour';
	if (value < 1)
		return `${Math.round(value * 24)} ${Math.round(value * 24) === 1 ? 'hour' : 'hours'}`;
	return `${value} ${value === 1 ? 'day' : 'days'}`;
}

// What the database answers for one column: a built-in stage, or a custom stage with its own name and the
// built-in stage it sits after.
export type RawStageTime = {
	stage: string | null;
	custom_stage_id: string | null;
	name: string | null;
	after_stage: string | null;
	position: number | null;
	disabled: boolean | null;
	cards: number;
	still_there: number;
	median_days: number;
	average_days: number;
};

export type StageTime = {
	key: string;
	label: string;
	group: 'Requests' | 'Quotes';
	/** An owner-made column. `retired` when it has since been switched off. */
	custom: boolean;
	retired: boolean;
	cards: number;
	still_there: number;
	median_days: number;
	average_days: number;
};

// Left to right, the way the board draws its columns: each built-in stage, then the custom stages placed
// after it in their saved order.
export function orderStageTimes(rows: RawStageTime[]): StageTime[] {
	const ordered: StageTime[] = [];
	const builtIns: readonly AnyBoardStage[] = [...BOARD_STAGES, ...QUOTE_BOARD_STAGES];

	for (const stage of builtIns) {
		const group = (BOARD_STAGES as readonly string[]).includes(stage) ? 'Requests' : 'Quotes';
		const numbers = (row: RawStageTime) => ({
			cards: row.cards,
			still_there: row.still_there,
			median_days: row.median_days,
			average_days: row.average_days
		});

		const own = rows.find((row) => row.custom_stage_id === null && row.stage === stage);
		if (own) {
			ordered.push({
				key: stage,
				label: ALL_STAGE_LABELS[stage],
				group,
				custom: false,
				retired: false,
				...numbers(own)
			});
		}

		const customs = rows
			.filter((row) => row.custom_stage_id !== null && row.after_stage === stage)
			.sort(
				(a, b) =>
					Number(Boolean(a.disabled)) - Number(Boolean(b.disabled)) ||
					(a.position ?? 0) - (b.position ?? 0) ||
					(a.name ?? '').localeCompare(b.name ?? '')
			);
		for (const row of customs) {
			ordered.push({
				key: row.custom_stage_id as string,
				label: row.name ?? 'Custom stage',
				group,
				custom: true,
				retired: Boolean(row.disabled),
				...numbers(row)
			});
		}
	}

	return ordered;
}
