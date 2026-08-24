import { describe, expect, it } from 'vitest';
import { encodeBoardCursor, readBoardCursor, resolveDateRange } from './board';

// Toronto, because it keeps daylight saving: a preset that quietly used UTC midnight would be an hour
// out for four months of the year and would show yesterday's cards under "This month" every evening.
const TORONTO = 'America/Toronto';

describe('board cursor', () => {
	it('survives a round trip', () => {
		const cursor = {
			column: 'new_request' as const,
			sort: 'created' as const,
			phase: 1 as const,
			value: '2026-08-19T04:00:00.000Z',
			id: '9c3f5a0e-1111-4222-8333-444455556666'
		};
		expect(readBoardCursor(encodeBoardCursor(cursor))).toEqual(cursor);
	});

	it('keeps a money value exactly as it was written', () => {
		const cursor = {
			column: 'assessment' as const,
			sort: 'value' as const,
			phase: 1 as const,
			value: '15250.50',
			id: '9c3f5a0e-1111-4222-8333-444455556666'
		};
		expect(readBoardCursor(encodeBoardCursor(cursor))?.value).toBe('15250.50');
	});

	it('remembers which half of a value sort it came from', () => {
		const unestimated = {
			column: 'quote_draft' as const,
			sort: 'value' as const,
			phase: 2 as const,
			value: '',
			id: '9c3f5a0e-1111-4222-8333-444455556666'
		};
		expect(readBoardCursor(encodeBoardCursor(unestimated))?.phase).toBe(2);
	});

	it('remembers which column it was cut from', () => {
		const cursor = {
			column: 'assessment' as const,
			sort: 'stage' as const,
			phase: 1 as const,
			value: '2026-08-19T04:00:00.000Z',
			id: '9c3f5a0e-1111-4222-8333-444455556666'
		};
		expect(readBoardCursor(encodeBoardCursor(cursor))?.column).toBe('assessment');
	});

	it('refuses anything it did not write', () => {
		expect(readBoardCursor(null)).toBeNull();
		expect(readBoardCursor('')).toBeNull();
		expect(readBoardCursor('nonsense')).toBeNull();
		expect(readBoardCursor('new_request:title:1:abc|id')).toBeNull();
		expect(readBoardCursor('new_request:created:9:abc|id')).toBeNull();
		expect(readBoardCursor('new_request:created:1:abc|')).toBeNull();
		// A column name that is not a column, and the old three-field shape from before columns were
		// bound in. Both are markers this build never wrote.
		expect(readBoardCursor('request_closed:created:1:abc|id')).toBeNull();
		expect(readBoardCursor('created:1:abc|id')).toBeNull();
	});
});

describe('created-date presets', () => {
	// A Wednesday afternoon in Toronto, written as the instant it really is.
	const wednesday = new Date('2026-08-19T18:30:00.000Z');

	it('leaves an unfiltered board unbounded', () => {
		expect(resolveDateRange('all', TORONTO, undefined, wednesday)).toEqual({
			from: null,
			to: null
		});
	});

	it('starts this month at local midnight on the first', () => {
		const range = resolveDateRange('this_month', TORONTO, undefined, wednesday);
		// Midnight in Toronto in August is 04:00 UTC.
		expect(range.from).toBe('2026-08-01T04:00:00.000Z');
		expect(range.to).toBe('2026-08-20T04:00:00.000Z');
	});

	it('reads last month as the whole previous calendar month', () => {
		const range = resolveDateRange('last_month', TORONTO, undefined, wednesday);
		expect(range.from).toBe('2026-07-01T04:00:00.000Z');
		expect(range.to).toBe('2026-08-01T04:00:00.000Z');
	});

	it('crosses the new year without leaving December behind', () => {
		const newYear = new Date('2026-01-08T15:00:00.000Z');
		const range = resolveDateRange('last_month', TORONTO, undefined, newYear);
		// Midnight in Toronto in winter is 05:00 UTC.
		expect(range.from).toBe('2025-12-01T05:00:00.000Z');
		expect(range.to).toBe('2026-01-01T05:00:00.000Z');
	});

	it('reads last week as the previous Sunday-to-Saturday week', () => {
		const range = resolveDateRange('last_week', TORONTO, undefined, wednesday);
		// This week began Sunday 16 August, so last week is the 9th up to the 16th.
		expect(range.from).toBe('2026-08-09T04:00:00.000Z');
		expect(range.to).toBe('2026-08-16T04:00:00.000Z');
	});

	it('counts the last 30 days as including today', () => {
		const range = resolveDateRange('last_30_days', TORONTO, undefined, wednesday);
		expect(range.from).toBe('2026-07-21T04:00:00.000Z');
		expect(range.to).toBe('2026-08-20T04:00:00.000Z');
	});

	it('counts the last 12 months from the same date a year ago through today', () => {
		const range = resolveDateRange('last_12_months', TORONTO, undefined, wednesday);
		expect(range.from).toBe('2025-08-19T04:00:00.000Z');
		expect(range.to).toBe('2026-08-20T04:00:00.000Z');
	});

	it('starts this year on 1 January', () => {
		const range = resolveDateRange('this_year', TORONTO, undefined, wednesday);
		expect(range.from).toBe('2026-01-01T05:00:00.000Z');
		expect(range.to).toBe('2026-08-20T04:00:00.000Z');
	});

	it('includes the last day a custom range names', () => {
		const range = resolveDateRange(
			'custom',
			TORONTO,
			{ from: '2026-03-01', to: '2026-03-31' },
			wednesday
		);
		expect(range.from).toBe('2026-03-01T05:00:00.000Z');
		// The end is the first moment of 1 April, so the whole of 31 March is in.
		expect(range.to).toBe('2026-04-01T04:00:00.000Z');
	});

	it('handles a custom range that starts before the clocks change and ends after', () => {
		// Toronto springs forward on 8 March 2026: the start is a 05:00 UTC midnight, the end a 04:00 one.
		const range = resolveDateRange(
			'custom',
			TORONTO,
			{ from: '2026-03-05', to: '2026-03-10' },
			wednesday
		);
		expect(range.from).toBe('2026-03-05T05:00:00.000Z');
		expect(range.to).toBe('2026-03-11T04:00:00.000Z');
	});

	it('lets a custom range be open at either end', () => {
		expect(resolveDateRange('custom', TORONTO, { from: '2026-03-01' }, wednesday).to).toBeNull();
		expect(resolveDateRange('custom', TORONTO, { to: '2026-03-01' }, wednesday).from).toBeNull();
	});

	it('gives a contractor in Auckland their own calendar, not ours', () => {
		const range = resolveDateRange('this_month', 'Pacific/Auckland', undefined, wednesday);
		// 20 August in Auckland has already started while it is still the 19th in Toronto.
		expect(range.from).toBe('2026-07-31T12:00:00.000Z');
		expect(range.to).toBe('2026-08-20T12:00:00.000Z');
	});
});
