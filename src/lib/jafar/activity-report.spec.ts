import { describe, expect, it } from 'vitest';
import {
	readReportPeriod,
	reportRange,
	reportRows,
	reportTotals,
	type ReportRow
} from './activity-report';

const row = (source: ReportRow['source'], counts: Partial<ReportRow> = {}): ReportRow => ({
	source,
	researched: 0,
	approved: 0,
	reached: 0,
	messages_sent: 0,
	replied: 0,
	messages_received: 0,
	calls_booked: 0,
	calls_held: 0,
	pricing_shared: 0,
	won: 0,
	won_usd_cents: 0,
	lost: 0,
	...counts
});

describe('activity report periods', () => {
	// Thursday 9 October 2026.
	const today = new Date(2026, 9, 9);

	it('works out each period’s first and last day, both included', () => {
		expect(reportRange('this_week', today)).toEqual({ from: '2026-10-05', to: '2026-10-09' });
		expect(reportRange('this_month', today)).toEqual({ from: '2026-10-01', to: '2026-10-09' });
		expect(reportRange('last_month', today)).toEqual({ from: '2026-09-01', to: '2026-09-30' });
		expect(reportRange('last_90_days', today)).toEqual({ from: '2026-07-12', to: '2026-10-09' });
		expect(reportRange('this_year', today)).toEqual({ from: '2026-01-01', to: '2026-10-09' });
		expect(reportRange('all_time', today)).toEqual({ from: null, to: '2026-10-09' });
	});

	it('starts the week on Monday, even on a Sunday', () => {
		expect(reportRange('this_week', new Date(2026, 9, 11))).toEqual({
			from: '2026-10-05',
			to: '2026-10-11'
		});
	});

	it('crosses into last year for January’s last month', () => {
		expect(reportRange('last_month', new Date(2027, 0, 15))).toEqual({
			from: '2026-12-01',
			to: '2026-12-31'
		});
	});

	it('falls back to this month for a hand-edited link', () => {
		expect(readReportPeriod(new URLSearchParams('period=last_year'))).toBe('this_month');
		expect(readReportPeriod(new URLSearchParams('period=all_time'))).toBe('all_time');
	});
});

describe('activity report rows', () => {
	it('keeps sources with something in the period, in the Leads form’s order', () => {
		const rows = [row('referral', { won: 1 }), row('event'), row('google_maps', { reached: 2 })];
		expect(reportRows(rows).map((entry) => entry.source)).toEqual(['google_maps', 'referral']);
	});

	it('adds people and messages separately across sources', () => {
		const totals = reportTotals([
			row('google_maps', { reached: 2, messages_sent: 5, won: 1, won_usd_cents: 9900 }),
			row('referral', { reached: 1, messages_sent: 1 })
		]);
		expect(totals.reached).toBe(3);
		expect(totals.messages_sent).toBe(6);
		expect(totals.won).toBe(1);
		expect(totals.won_usd_cents).toBe(9900);
	});
});
