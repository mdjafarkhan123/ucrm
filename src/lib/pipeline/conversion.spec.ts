import { describe, expect, it } from 'vitest';
import {
	formatDays,
	formatRate,
	orderStageTimes,
	quoteWinRate,
	requestToQuoteRate,
	requestToWonRate,
	workWinRate,
	type RawStageTime
} from './conversion';

const requests = { total: 14, quoted: 5, won: 2, lost: 2, closed: 2, open: 8, open_unquoted: 6 };

describe('conversion rates', () => {
	it('keeps the three rates apart and never divides open work', () => {
		// 8 of the 14 have had the chance to be quoted or closed; 6 are open and still unquoted.
		expect(requestToQuoteRate(requests)).toEqual({ percent: 63, hits: 5, outOf: 8 });
		// 6 are no longer open; 2 of them were won.
		expect(requestToWonRate(requests)).toEqual({ percent: 33, hits: 2, outOf: 6 });
		// Open and abandoned quotes are in neither side of the division.
		expect(quoteWinRate({ total: 44, won: 4, lost: 3, open: 7, abandoned: 30 })).toEqual({
			percent: 57,
			hits: 4,
			outOf: 7
		});
	});

	it('counts work closed with no result against the win rate, as not won', () => {
		expect(workWinRate({ total: 4, won: 1, lost: 1, closed: 1, open: 1 }).percent).toBe(33);
	});

	it('shows a dash, never 0%, while everything is still open', () => {
		const allOpen = { total: 3, quoted: 0, won: 0, lost: 0, closed: 0, open: 3, open_unquoted: 3 };

		expect(requestToWonRate(allOpen).percent).toBeNull();
		expect(formatRate(requestToWonRate(allOpen))).toBe('—');
		expect(formatRate(requestToWonRate(requests))).toBe('33%');
	});
});

describe('formatDays', () => {
	it('reads short stays in hours', () => {
		expect(formatDays(0)).toBe('Under 1 hour');
		expect(formatDays(0.5)).toBe('12 hours');
		expect(formatDays(1)).toBe('1 day');
		expect(formatDays(23.9)).toBe('23.9 days');
	});
});

describe('orderStageTimes', () => {
	const numbers = { cards: 1, still_there: 0, median_days: 1, average_days: 1 };
	const builtIn = (stage: string): RawStageTime => ({
		stage,
		custom_stage_id: null,
		name: null,
		after_stage: null,
		position: null,
		disabled: false,
		...numbers
	});
	const custom = (id: string, name: string, after: string, position: number, disabled = false) =>
		({
			stage: null,
			custom_stage_id: id,
			name,
			after_stage: after,
			position,
			disabled,
			...numbers
		}) satisfies RawStageTime;

	it('follows the board left to right, custom stages after the stage they sit behind', () => {
		const ordered = orderStageTimes([
			custom('c2', 'Second follow-up', 'quote_awaiting_response', 1),
			builtIn('quote_awaiting_response'),
			custom('c0', 'Old column', 'quote_awaiting_response', 0, true),
			builtIn('new_request'),
			custom('c1', 'First follow-up', 'quote_awaiting_response', 0),
			builtIn('quote_draft')
		]);

		expect(ordered.map((stage) => stage.label)).toEqual([
			'New requests',
			'Draft',
			'Awaiting response',
			'First follow-up',
			'Second follow-up',
			'Old column'
		]);
		expect(ordered[0].group).toBe('Requests');
		expect(ordered[3]).toMatchObject({ group: 'Quotes', custom: true, retired: false });
		expect(ordered[5].retired).toBe(true);
	});
});
