import { describe, it, expect } from 'vitest';
import { parseTime } from '@internationalized/date';
import { addMinutesToTime, reconcileTimeRange } from './date-time';

describe('addMinutesToTime', () => {
	it('moves a time later', () => {
		expect(addMinutesToTime(parseTime('09:30'), 60).toString()).toBe('10:30:00');
	});

	it('never rolls past the last minute of the day', () => {
		expect(addMinutesToTime(parseTime('23:30'), 60).toString()).toBe('23:59:00');
	});
});

describe('reconcileTimeRange', () => {
	const range = (start: string | undefined, end: string | undefined) => ({
		start: start ? parseTime(start) : undefined,
		end: end ? parseTime(end) : undefined
	});

	it('leaves a healthy range alone', () => {
		const next = range('09:00', '11:00:00');
		expect(reconcileTimeRange(range('09:00', '10:00'), next)).toBe(next);
	});

	it('leaves a half-empty range alone', () => {
		const onlyStart = range('09:00', undefined);
		expect(reconcileTimeRange(range(undefined, undefined), onlyStart)).toBe(onlyStart);
	});

	it('carries the visit length when a later start crosses the end', () => {
		const moved = reconcileTimeRange(range('09:00', '10:00'), range('11:00:00', '10:00'));
		expect(moved.start?.toString()).toBe('11:00:00');
		expect(moved.end?.toString()).toBe('12:00:00');
	});

	it('assumes an hour when there was no earlier length to carry', () => {
		const picked = reconcileTimeRange(range(undefined, '10:00'), range('14:00:00', '10:00'));
		expect(picked.start?.toString()).toBe('14:00:00');
		expect(picked.end?.toString()).toBe('15:00:00');
	});

	it('pulls the start back when the end is dragged before it', () => {
		const pulled = reconcileTimeRange(range('09:00', '12:00:00'), range('09:00', '08:00:00'));
		expect(pulled.start?.toString()).toBe('05:00:00');
		expect(pulled.end?.toString()).toBe('08:00:00');
	});
});
