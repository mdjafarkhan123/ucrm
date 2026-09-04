import { describe, expect, it } from 'vitest';
import { calendarDay, clockMinutesInZone, zonedTimeToUtc } from './calendar-day';

describe('zonedTimeToUtc', () => {
	it('books a wall-clock day/time in the organization timezone, not the machine timezone', () => {
		// The bug this guards: an assessment typed as "Fri 4 Sept, 12:00 PM" against an org on
		// Asia/Dhaka (UTC+6) must land at 2026-09-04 06:00 UTC, wherever the browser itself sits.
		const instant = zonedTimeToUtc('2026-09-04', '12:00', 'Asia/Dhaka');
		expect(instant?.toISOString()).toBe('2026-09-04T06:00:00.000Z');
	});

	it('round-trips through calendarDay/clockMinutesInZone for the same timezone', () => {
		const timezone = 'America/Denver';
		const instant = zonedTimeToUtc('2026-09-04', '09:30', timezone);
		expect(instant).not.toBeNull();
		expect(calendarDay(instant!, timezone)).toBe('2026-09-04');
		expect(clockMinutesInZone(instant!, timezone)).toBe(9 * 60 + 30);
	});

	it('resolves midnight correctly across a UTC-behind timezone', () => {
		const instant = zonedTimeToUtc('2026-01-15', '00:00', 'America/Denver');
		// MST is UTC-7 in January, so local midnight is 07:00 UTC the same day.
		expect(instant?.toISOString()).toBe('2026-01-15T07:00:00.000Z');
	});

	it('returns null for an unparseable day or time', () => {
		expect(zonedTimeToUtc('not-a-day', '12:00', 'UTC')).toBeNull();
		expect(zonedTimeToUtc('2026-09-04', 'not-a-time', 'UTC')).toBeNull();
	});
});
