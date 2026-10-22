import { describe, expect, it } from 'vitest';
import { hoursSummary, openTodayText } from './home-summary';

const day = (weekday: number, opens = '08:00:00', closes = '17:00:00') => ({
	weekday,
	is_open: true,
	is_open_24h: false,
	opens_at: opens,
	closes_at: closes,
	period_index: 0
});

describe('hoursSummary', () => {
	it('joins a run of days with the same hours', () => {
		expect(hoursSummary([1, 2, 3, 4, 5].map((weekday) => day(weekday)))).toBe('Mon–Fri 8–5');
	});
	it('keeps a gap as separate runs', () => {
		expect(hoursSummary([0, 1, 2, 3, 4, 6].map((weekday) => day(weekday, '09:00:00')))).toBe(
			'Sun–Thu, Sat 9–5'
		);
	});
	it('says how many days are open when the hours differ', () => {
		expect(hoursSummary([day(1), day(2, '10:00:00')])).toBe('Open 2 days');
	});
	it('reports a week with nothing open', () => {
		expect(hoursSummary([{ ...day(1), is_open: false }])).toBe('Closed all week');
	});
});

describe('openTodayText', () => {
	it('reads today in the business time zone', () => {
		const monday = new Date('2026-10-19T18:00:00Z');
		expect(openTodayText([day(1)], 'America/Vancouver', monday)).toBe('8 AM – 5 PM');
		expect(openTodayText([day(2)], 'America/Vancouver', monday)).toBe('Closed today');
	});
});
