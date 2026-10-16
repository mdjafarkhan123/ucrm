import { describe, expect, it } from 'vitest';
import { clientOverviewWindows } from './overview';

describe('Clients overview windows', () => {
	it('counts the past 30 calendar days including today, in the organization timezone', () => {
		// 10:00 on Oct 14 in Vancouver (UTC-7 in October).
		const windows = clientOverviewWindows('America/Vancouver', new Date('2026-10-14T17:00:00Z'));
		expect(windows.period).toEqual({ from: '2026-09-15', to: '2026-10-14' });
		expect(windows.current_since).toBe('2026-09-15T07:00:00.000Z');
		expect(windows.previous_since).toBe('2026-08-16T07:00:00.000Z');
		expect(windows.year_since).toBe('2026-01-01T08:00:00.000Z');
	});

	it('uses the local day, not the UTC one, late in the evening', () => {
		// 23:30 on Dec 31 in New York is already Jan 1 in UTC; the year has not turned there yet.
		const windows = clientOverviewWindows('America/New_York', new Date('2027-01-01T04:30:00Z'));
		expect(windows.period.to).toBe('2026-12-31');
		expect(windows.year_since).toBe('2026-01-01T05:00:00.000Z');
	});

	it('rolls the window back across a month boundary', () => {
		const windows = clientOverviewWindows('UTC', new Date('2026-03-05T12:00:00Z'));
		expect(windows.period.from).toBe('2026-02-04');
		expect(windows.previous_since).toBe('2026-01-05T00:00:00.000Z');
	});
});
