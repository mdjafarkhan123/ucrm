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

// Keeps a start/end pair readable the way scheduling apps do: whichever boundary the person just set
// stays put, and the other one carries the visit's length over, so the end never lands at or before
// the start. A range nobody broke comes back untouched.
export function reconcileTimeRange(previous: TimeRangeValue, next: TimeRangeValue): TimeRangeValue {
	if (!next.start || !next.end || isTimeRangeValid(next)) return next;

	const carried =
		previous.start && previous.end
			? (timeToMinutes(previous.end) ?? 0) - (timeToMinutes(previous.start) ?? 0)
			: DEFAULT_RANGE_MINUTES;
	const duration = carried > 0 ? carried : DEFAULT_RANGE_MINUTES;

	// The end stayed where it was, so the start crossed it: push the end out instead.
	if (!previous.end || timeToMinutes(previous.end) === timeToMinutes(next.end)) {
		return { start: next.start, end: addMinutesToTime(next.start, duration) };
	}

	// The end was pulled before the start: move the start back to keep the length.
	const startTotal = Math.max((timeToMinutes(next.end) ?? 0) - duration, 0);
	return { start: new Time(Math.floor(startTotal / 60), startTotal % 60), end: next.end };
}
