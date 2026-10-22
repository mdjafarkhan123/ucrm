import { describe, expect, it } from 'vitest';
import { amountAndDateSample, timeThere, timezoneLabel } from './profile-format';

const noon = new Date('2026-10-22T19:00:00Z');

describe('profile-format', () => {
	it('words a time zone with its city, name and offset', () => {
		expect(timezoneLabel('America/Vancouver', noon)).toBe(
			'Vancouver · Pacific Daylight Time (UTC−7)'
		);
		expect(timezoneLabel('UTC', noon)).toContain('UTC');
	});

	it('shows the time and day in that zone', () => {
		expect(timeThere('America/Vancouver', noon)).toBe('12:00 PM · Thursday, Oct 22');
	});

	it('shows a sample amount and date', () => {
		expect(amountAndDateSample('CAD', 'America/Vancouver', 'en-CA', noon)).toContain('1,250.00');
	});

	it('falls back quietly for a zone it does not know', () => {
		expect(timeThere('Not/AZone', noon)).toBe('');
		expect(timezoneLabel('Not/AZone', noon)).toBe('Not/AZone');
	});
});
