// Wording for the dark New clients card. The counts come from the database; this only says how two of
// them compare and which days the window covers.

export type CountChange = { direction: 'up' | 'down' | 'same'; text: string };

// "4 more than the 30 days before". With nothing in either window there is nothing to compare.
export function newClientsChange(current: number, previous: number): CountChange | null {
	if (current === 0 && previous === 0) return null;
	const difference = current - previous;
	if (difference === 0) return { direction: 'same', text: 'Same as the 30 days before' };
	return {
		direction: difference > 0 ? 'up' : 'down',
		text: `${Math.abs(difference)} ${difference > 0 ? 'more' : 'fewer'} than the 30 days before`
	};
}

// "Sep 15 – Oct 14" from two calendar days (YYYY-MM-DD), read as plain dates so no timezone moves them.
export function periodLabel(from: string, to: string, locale?: string) {
	const format = new Intl.DateTimeFormat(locale, {
		month: 'short',
		day: 'numeric',
		timeZone: 'UTC'
	});
	const day = (value: string) => {
		const [year, month, date] = value.split('-').map(Number);
		return format.format(new Date(Date.UTC(year, month - 1, date)));
	};
	return `${day(from)} – ${day(to)}`;
}
