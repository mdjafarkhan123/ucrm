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
