// Home's "Business performance" compares this month so far with last month up to the same day, as the
// approved plan says (docs/home-and-reports-behavior-contract.md). All days are plain `YYYY-MM-DD` strings in
// the business's own calendar; the money reports read a range as `from` included, `to` excluded.

export type DayRange = { from: string; to: string };

export type MonthComparison = {
	current: DayRange;
	previous: DayRange;
	/** "Oct 1–14" and "Sep 1–14": the two spans the bars are labelled with. */
	currentLabel: string;
	previousLabel: string;
};

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function parts(day: string) {
	const [year, month, date] = day.split('-').map(Number);
	return { year, month, date };
}

function format(year: number, month: number, date: number) {
	return `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-${String(date).padStart(2, '0')}`;
}

export function addDays(day: string, amount: number): string {
	const { year, month, date } = parts(day);
	const moved = new Date(Date.UTC(year, month - 1, date + amount));
	return format(moved.getUTCFullYear(), moved.getUTCMonth() + 1, moved.getUTCDate());
}

function daysInMonth(year: number, month: number) {
	return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function spanLabel(year: number, month: number, lastDay: number) {
	return `${MONTHS[month - 1]} 1–${lastDay}`;
}

/** This month up to and including `today`, against last month up to the same day. On the 31st, a shorter
 * last month is compared whole. */
export function monthComparison(today: string): MonthComparison {
	const { year, month, date } = parts(today);
	const previousYear = month === 1 ? year - 1 : year;
	const previousMonth = month === 1 ? 12 : month - 1;
	const previousLastDay = Math.min(date, daysInMonth(previousYear, previousMonth));
	return {
		current: { from: format(year, month, 1), to: addDays(today, 1) },
		previous: {
			from: format(previousYear, previousMonth, 1),
			to: addDays(format(previousYear, previousMonth, previousLastDay), 1)
		},
		currentLabel: spanLabel(year, month, date),
		previousLabel: spanLabel(previousYear, previousMonth, previousLastDay)
	};
}

/** The change as a whole percentage, or null when there is nothing before it to compare with. */
export function percentChange(current: number, previous: number): number | null {
	if (previous <= 0) return null;
	return Math.round(((current - previous) / previous) * 100);
}
