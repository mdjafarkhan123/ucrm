import { timeFromString, type TimeRangeValue } from '$lib/components/ui/date-time';

// One weekday as the weekly-hours editor holds it while someone is filling it in. Index 0 is Sunday.
export type DayState = { isOpen: boolean; is24h: boolean; periods: TimeRangeValue[] };

export function blankDay(isOpen: boolean): DayState {
	return {
		isOpen,
		is24h: false,
		periods: isOpen ? [{ start: timeFromString('09:00'), end: timeFromString('17:00') }] : []
	};
}

export function closedWeek(): DayState[] {
	return [0, 1, 2, 3, 4, 5, 6].map(() => blankDay(false));
}

/** Monday to Friday, 8am to 5pm — the starting point most trades only have to adjust. */
export function suggestedWeek(): DayState[] {
	return [0, 1, 2, 3, 4, 5, 6].map((weekday) => {
		const open = weekday >= 1 && weekday <= 5;
		return open
			? {
					isOpen: true,
					is24h: false,
					periods: [{ start: timeFromString('08:00'), end: timeFromString('17:00') }]
				}
			: blankDay(false);
	});
}
