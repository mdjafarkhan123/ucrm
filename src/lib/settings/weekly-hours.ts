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

/** One open stretch drawn on a day's 24-hour bar, placed in percent of the day. */
export type HoursBlock = { left: number; width: number; label: string };

const DAY_MINUTES = 24 * 60;

function clockParts(minutes: number) {
	const hour = Math.floor(minutes / 60) % 24;
	return {
		hour: hour % 12 || 12,
		minute: minutes % 60,
		meridiem: hour < 12 ? 'AM' : 'PM'
	};
}

function clockText(minutes: number, withMeridiem: boolean, padMinutes: boolean) {
	const { hour, minute, meridiem } = clockParts(minutes);
	const time = minute || padMinutes ? `${hour}:${String(minute).padStart(2, '0')}` : `${hour}`;
	return withMeridiem ? `${time} ${meridiem}` : time;
}

/** "8:00 AM – 5:00 PM" when the block is wide enough; "7–11 AM" or "8 AM–12 PM" when it is short. */
export function blockLabel(start: number, end: number) {
	if (end - start >= 6 * 60) return `${clockText(start, true, true)} – ${clockText(end, true, true)}`;
	const sameHalf = clockParts(start).meridiem === clockParts(end).meridiem;
	return sameHalf
		? `${clockText(start, false, false)}–${clockText(end, true, false)}`
		: `${clockText(start, true, false)}–${clockText(end, true, false)}`;
}

/** What a day's bar shows: nothing when closed, the whole bar for 24 hours, otherwise each valid period.
 *  A period still being typed (no start, no end, or ending before it starts) draws nothing yet. */
export function dayBlocks(day: DayState): HoursBlock[] {
	if (!day.isOpen) return [];
	if (day.is24h) return [{ left: 0, width: 100, label: 'Open 24 hours' }];
	return day.periods.flatMap(({ start, end }) => {
		if (!start || !end) return [];
		const from = start.hour * 60 + start.minute;
		const to = end.hour * 60 + end.minute;
		if (to <= from) return [];
		return [
			{
				left: (from / DAY_MINUTES) * 100,
				width: ((to - from) / DAY_MINUTES) * 100,
				label: blockLabel(from, to)
			}
		];
	});
}
