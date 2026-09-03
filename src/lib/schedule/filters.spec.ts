import { describe, expect, it } from 'vitest';
import {
	eachDayInWindow,
	reanchorScheduleDate,
	readScheduleFilters,
	scheduleFilterParams,
	scheduleWindow,
	shiftScheduleDate,
	type ScheduleFilters
} from '$lib/schedule/filters';
import { SCHEDULE_WINDOW_MAX_DAYS } from '$lib/server/validation/schedule.schema';

// 2026-09-02 is a Wednesday, so the week around it runs Sunday the 30th to Saturday the 5th.
const TODAY = '2026-09-02';
const EMPLOYEE = '11111111-2222-3333-4444-555555555555';

const read = (query: string) => readScheduleFilters(new URLSearchParams(query), TODAY);

describe('readScheduleFilters', () => {
	it('opens on today, this week, everyone and every status', () => {
		expect(read('')).toEqual<ScheduleFilters>({
			date: TODAY,
			view: 'week',
			employee: 'all',
			status: 'all'
		});
	});

	it('reads a whole shared link back', () => {
		expect(
			read(`date=2026-10-05&view=day&employee=${EMPLOYEE}&status=late`)
		).toEqual<ScheduleFilters>({
			date: '2026-10-05',
			view: 'day',
			employee: EMPLOYEE,
			status: 'late'
		});
	});

	it('falls back rather than breaking on a date that is not a real day', () => {
		expect(read('date=2026-02-31').date).toBe(TODAY);
		expect(read('date=yesterday').date).toBe(TODAY);
	});

	it('ignores a view, employee or status it does not recognise', () => {
		const filters = read('view=timeline&employee=someone&status=cancelled');
		expect(filters.view).toBe('week');
		expect(filters.employee).toBe('all');
		expect(filters.status).toBe('all');
	});
});

describe('scheduleFilterParams', () => {
	it('writes nothing for the default calendar, so a plain link stays plain', () => {
		const params = scheduleFilterParams(
			{ date: TODAY, view: 'week', employee: 'all', status: 'all' },
			TODAY
		);
		expect(params.toString()).toBe('');
	});

	it('round-trips everything that differs from the default', () => {
		const filters: ScheduleFilters = {
			date: '2026-10-05',
			view: 'month',
			employee: 'unassigned',
			status: 'completed'
		};
		expect(readScheduleFilters(scheduleFilterParams(filters, TODAY), TODAY)).toEqual(filters);
	});
});

describe('scheduleWindow', () => {
	it('asks for one day, a Sunday-to-Saturday week, or the padded month the grid draws', () => {
		expect(scheduleWindow(TODAY, 'day')).toEqual({ from: TODAY, to: TODAY });
		expect(scheduleWindow(TODAY, 'week')).toEqual({ from: '2026-08-30', to: '2026-09-05' });
		// September 2026 starts on a Tuesday, so the grid opens on the Sunday before it.
		expect(scheduleWindow(TODAY, 'month')).toEqual({ from: '2026-08-30', to: '2026-10-10' });
	});

	it('starts on the 1st when the month already starts on a Sunday', () => {
		expect(scheduleWindow('2026-02-14', 'month')).toEqual({ from: '2026-02-01', to: '2026-03-14' });
	});

	it('never asks for more days than the window route allows', () => {
		for (const date of [TODAY, '2026-02-14', '2027-01-31', '2028-02-29']) {
			const window = scheduleWindow(date, 'month');
			expect(eachDayInWindow(window)).toHaveLength(SCHEDULE_WINDOW_MAX_DAYS);
		}
	});
});

describe('shiftScheduleDate', () => {
	it('moves by exactly the window the person is looking at', () => {
		expect(shiftScheduleDate(TODAY, 'day', 1)).toBe('2026-09-03');
		expect(shiftScheduleDate(TODAY, 'week', -1)).toBe('2026-08-26');
		expect(shiftScheduleDate(TODAY, 'month', 1)).toBe('2026-10-02');
	});

	it('clamps a month step onto a month that is too short for the day', () => {
		expect(shiftScheduleDate('2026-01-31', 'month', 1)).toBe('2026-02-28');
	});
});

describe('reanchorScheduleDate', () => {
	it('keeps the day when leaving Week or Day', () => {
		expect(reanchorScheduleDate(TODAY, 'week', 'day')).toBe(TODAY);
		expect(reanchorScheduleDate(TODAY, 'day', 'month')).toBe(TODAY);
	});

	it('lands on the first of the month when leaving Month', () => {
		expect(reanchorScheduleDate('2026-09-17', 'month', 'week')).toBe('2026-09-01');
	});
});

describe('eachDayInWindow', () => {
	it('walks the window inclusively, across a month boundary', () => {
		expect(eachDayInWindow({ from: '2026-08-30', to: '2026-09-02' })).toEqual([
			'2026-08-30',
			'2026-08-31',
			'2026-09-01',
			'2026-09-02'
		]);
	});

	it('gives a single day for a one-day window', () => {
		expect(eachDayInWindow({ from: TODAY, to: TODAY })).toEqual([TODAY]);
	});
});
