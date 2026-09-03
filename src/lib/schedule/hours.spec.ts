import { describe, expect, it } from 'vitest';
import { earliestWorkingMinute, weekdayOf, workingWeek } from '$lib/schedule/hours';
import type { BusinessHourPeriod } from '$lib/schedule/api';

function period(overrides: Partial<BusinessHourPeriod> = {}): BusinessHourPeriod {
	return {
		weekday: 1,
		period_index: 0,
		is_open: true,
		is_open_24h: false,
		opens_at: '08:00:00',
		closes_at: '17:00:00',
		...overrides
	};
}

describe('workingWeek', () => {
	it('has nothing to shade without a confirmed weekly pattern', () => {
		expect(workingWeek({ hours_mode: 'not_configured', hours: [] })).toBeNull();
		expect(workingWeek({ hours_mode: 'appointment_only', hours: [period()] })).toBeNull();
	});

	it('has nothing to shade when every weekday is closed', () => {
		expect(workingWeek({ hours_mode: 'weekly', hours: [period({ is_open: false })] })).toBeNull();
	});

	it('reads an open weekday as one band', () => {
		const week = workingWeek({ hours_mode: 'weekly', hours: [period()] });
		expect(week?.get(1)).toEqual([{ start: 480, end: 1020 }]);
	});

	it('keeps a lunch break as two bands', () => {
		const week = workingWeek({
			hours_mode: 'weekly',
			hours: [
				period({ opens_at: '08:00:00', closes_at: '12:00:00' }),
				period({ period_index: 1, opens_at: '13:00:00', closes_at: '17:00:00' })
			]
		});
		expect(week?.get(1)).toEqual([
			{ start: 480, end: 720 },
			{ start: 780, end: 1020 }
		]);
	});

	it('merges two rows that overlap into one band', () => {
		const week = workingWeek({
			hours_mode: 'weekly',
			hours: [
				period({ opens_at: '08:00:00', closes_at: '13:00:00' }),
				period({ period_index: 1, opens_at: '12:00:00', closes_at: '17:00:00' })
			]
		});
		expect(week?.get(1)).toEqual([{ start: 480, end: 1020 }]);
	});

	it('reads an all-day weekday as the whole day', () => {
		const week = workingWeek({
			hours_mode: 'weekly',
			hours: [period({ is_open_24h: true, opens_at: null, closes_at: null })]
		});
		expect(week?.get(1)).toEqual([{ start: 0, end: 1440 }]);
	});

	it('skips a row that closes before it opens', () => {
		const week = workingWeek({
			hours_mode: 'weekly',
			hours: [period({ opens_at: '17:00:00', closes_at: '08:00:00' })]
		});
		expect(week).toBeNull();
	});
});

describe('weekdayOf', () => {
	it('reads the weekday of a plain day', () => {
		expect(weekdayOf('2026-09-02')).toBe(3);
		expect(weekdayOf('2026-08-30')).toBe(0);
	});
});

describe('earliestWorkingMinute', () => {
	it('has no answer without a pattern', () => {
		expect(earliestWorkingMinute(null)).toBeNull();
	});

	it('finds the earliest opening in the week', () => {
		const week = workingWeek({
			hours_mode: 'weekly',
			hours: [
				period({ weekday: 1, opens_at: '08:00:00' }),
				period({ weekday: 2, opens_at: '06:30:00' })
			]
		});
		expect(earliestWorkingMinute(week)).toBe(390);
	});
});
