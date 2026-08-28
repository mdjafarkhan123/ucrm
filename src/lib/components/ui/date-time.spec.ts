import { describe, expect, it } from 'vitest';
import { Time } from '@internationalized/date';
import {
	addMinutesToTime,
	formatTimeText,
	isTimeRangeValid,
	parseTimeText,
	reconcileTimeRange,
	timeToString
} from './date-time';

describe('time text', () => {
	it.each([
		['9', '09:00'],
		['9am', '09:00'],
		['9:30', '09:30'],
		['2:05 pm', '14:05'],
		['14:00', '14:00'],
		['930am', '09:30'],
		['1437', '14:37']
	])('parses %s', (input, expected) => {
		expect(timeToString(parseTimeText(input))).toBe(expected);
	});

	it('treats an empty field as unset', () => {
		expect(parseTimeText('')).toBeUndefined();
	});

	it.each(['25:00', '12:70', '13pm', 'hello'])('rejects %s', (input) => {
		expect(parseTimeText(input)).toBeUndefined();
	});

	it('formats both supported hour cycles', () => {
		const value = new Time(14, 5);
		expect(formatTimeText(value, 12)).toBe('2:05 PM');
		expect(formatTimeText(value, 24)).toBe('14:05');
	});
});

describe('time range suggestion', () => {
	it('adds minutes without rolling into another day', () => {
		expect(timeToString(addMinutesToTime(new Time(9, 30), 60))).toBe('10:30');
		expect(timeToString(addMinutesToTime(new Time(23, 30), 60))).toBe('23:59');
	});

	it('suggests one hour when a fresh range receives a start', () => {
		const result = reconcileTimeRange(
			{ start: undefined, end: undefined },
			{ start: new Time(9, 0), end: undefined }
		);
		expect(timeToString(result.end)).toBe('10:00');
	});

	it('does not overwrite an existing end', () => {
		const end = new Time(10, 0);
		const result = reconcileTimeRange(
			{ start: new Time(9, 0), end },
			{ start: new Time(11, 0), end }
		);
		expect(result.end).toBe(end);
		expect(isTimeRangeValid(result)).toBe(false);
	});
});
