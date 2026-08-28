import { CalendarDate, Time, parseDate, parseTime } from '@internationalized/date';

export type CalendarPickerValue = CalendarDate | undefined;

export type TimeRangeValue = {
	start: Time | undefined;
	end: Time | undefined;
};

export type DateTimePickerValue = {
	date: CalendarDate | undefined;
	startTime: Time | undefined;
	endTime: Time | undefined;
};

export function calendarDateFromString(value: string | null | undefined) {
	if (!value) return undefined;

	try {
		return parseDate(value.slice(0, 10));
	} catch {
		return undefined;
	}
}

export function calendarDateToString(value: CalendarDate | undefined) {
	return value?.toString() ?? '';
}

export function timeFromString(value: string | null | undefined) {
	if (!value) return undefined;

	try {
		return parseTime(value.slice(0, 8));
	} catch {
		return undefined;
	}
}

export function timeToString(value: Time | undefined) {
	if (!value) return '';
	return `${String(value.hour).padStart(2, '0')}:${String(value.minute).padStart(2, '0')}`;
}

export function formatTimeText(value: Time | undefined, hourCycle: 12 | 24 = 12) {
	if (!value) return '';
	if (hourCycle === 24) return timeToString(value);

	const period = value.hour >= 12 ? 'PM' : 'AM';
	const hour = value.hour % 12 || 12;
	return `${hour}:${String(value.minute).padStart(2, '0')} ${period}`;
}

/** Parses the forgiving shorthand used by scheduling teams without accepting impossible times. */
export function parseTimeText(input: string): Time | undefined {
	const normalized = input.trim().toLowerCase().replace(/\./g, '').replace(/\s+/g, '');
	if (!normalized) return undefined;

	const periodMatch = normalized.match(/^(\d{1,2})(?::?(\d{2}))?(am|pm|a|p)$/);
	if (periodMatch) {
		const hour = Number(periodMatch[1]);
		const minute = Number(periodMatch[2] ?? 0);
		if (hour < 1 || hour > 12 || minute > 59) return undefined;
		const isPm = periodMatch[3].startsWith('p');
		return new Time((hour % 12) + (isPm ? 12 : 0), minute);
	}

	const colonMatch = normalized.match(/^(\d{1,2}):(\d{1,2})$/);
	if (colonMatch) {
		const hour = Number(colonMatch[1]);
		const minute = Number(colonMatch[2]);
		if (hour > 23 || minute > 59) return undefined;
		return new Time(hour, minute);
	}

	if (!/^\d{1,4}$/.test(normalized)) return undefined;
	if (normalized.length <= 2) {
		const hour = Number(normalized);
		if (hour > 23) return undefined;
		return new Time(hour, 0);
	}

	const hour = Number(normalized.slice(0, -2));
	const minute = Number(normalized.slice(-2));
	if (hour > 23 || minute > 59) return undefined;
	return new Time(hour, minute);
}

export function dateTimePickerValueFromLocalString(value: string | null | undefined) {
	if (!value) return emptyDateTimePickerValue();

	const [date, time] = value.split('T');
	return {
		date: calendarDateFromString(date),
		startTime: timeFromString(time),
		endTime: undefined
	};
}

export function dateTimePickerValueFromDate(value: Date) {
	return {
		date: new CalendarDate(value.getFullYear(), value.getMonth() + 1, value.getDate()),
		startTime: new Time(value.getHours(), value.getMinutes()),
		endTime: undefined
	};
}

export function dateTimePickerValueToLocalString(value: DateTimePickerValue) {
	if (!value.date || !value.startTime) return '';
	return `${calendarDateToString(value.date)}T${timeToString(value.startTime)}`;
}

export function localDateTimeToIso(value: string | null | undefined) {
	const localValue = dateTimePickerValueToLocalString(dateTimePickerValueFromLocalString(value));
	if (!localValue) return '';

	const date = new Date(localValue);
	return Number.isNaN(date.getTime()) ? '' : date.toISOString();
}

export function emptyDateTimePickerValue(): DateTimePickerValue {
	return { date: undefined, startTime: undefined, endTime: undefined };
}

export function timeToMinutes(value: Time | undefined) {
	return value ? value.hour * 60 + value.minute : undefined;
}

export function isTimeRangeValid(value: TimeRangeValue) {
	const start = timeToMinutes(value.start);
	const end = timeToMinutes(value.end);

	return start === undefined || end === undefined || end > start;
}

/** The visit length a fresh start assumes until someone says otherwise. */
export const DEFAULT_RANGE_MINUTES = 60;

/** Moves a time of day later without rolling past the last minute of the day. */
export function addMinutesToTime(time: Time, minutes: number) {
	const total = Math.min(time.hour * 60 + time.minute + minutes, 23 * 60 + 59);
	return new Time(Math.floor(total / 60), total % 60);
}

// A fresh start suggests a useful duration, but an end the user already chose is never overwritten.
export function reconcileTimeRange(previous: TimeRangeValue, next: TimeRangeValue): TimeRangeValue {
	if (!next.start || next.end || previous.end) return next;

	const previousDuration =
		previous.start && previous.end
			? (timeToMinutes(previous.end) ?? 0) - (timeToMinutes(previous.start) ?? 0)
			: DEFAULT_RANGE_MINUTES;
	const duration = previousDuration > 0 ? previousDuration : DEFAULT_RANGE_MINUTES;
	return { start: next.start, end: addMinutesToTime(next.start, duration) };
}
