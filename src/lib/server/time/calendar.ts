// Calendar days in the organization's own timezone, turned back into real instants.
//
// Two features need the same answer and must not each keep their own copy of it: Request statuses ask
// where today starts and ends, and the Pipeline's created-date filters ask where a week, a month or a
// year starts and ends. The rule lives here once, and the database is only ever handed instants.

// en-CA gives YYYY-MM-DD, so two calendar days can be compared as plain strings.
export function calendarDay(value: Date, timezone: string) {
	return new Intl.DateTimeFormat('en-CA', {
		timeZone: timezone,
		year: 'numeric',
		month: '2-digit',
		day: '2-digit'
	}).format(value);
}

const OFFSET_FORMAT_OPTIONS: Intl.DateTimeFormatOptions = {
	year: 'numeric',
	month: '2-digit',
	day: '2-digit',
	hour: '2-digit',
	minute: '2-digit',
	second: '2-digit',
	hourCycle: 'h23'
};

// How far the timezone runs ahead of UTC at one particular instant. Read off the formatted local clock,
// because that is the only thing Intl will tell us, and the answer changes twice a year.
function offsetMilliseconds(at: Date, timezone: string) {
	const parts = new Intl.DateTimeFormat('en-US', {
		timeZone: timezone,
		...OFFSET_FORMAT_OPTIONS
	}).formatToParts(at);
	const read = (type: Intl.DateTimeFormatPartTypes) =>
		Number(parts.find((part) => part.type === type)?.value ?? '0');
	const asIfUtc = Date.UTC(
		read('year'),
		read('month') - 1,
		read('day'),
		read('hour'),
		read('minute'),
		read('second')
	);
	// Milliseconds are not in the formatted parts, so compare whole seconds on both sides.
	return asIfUtc - Math.floor(at.getTime() / 1000) * 1000;
}

// Local midnight, converted back to a real instant. The offset is read twice: the first guess uses the
// offset happening now, the second uses the offset at the guessed midnight, which is what fixes the two
// days a year when the clocks change between the two.
//
// Day 0 and day 32 are deliberately allowed: Date.UTC rolls them into the neighbouring month, so a month
// boundary needs no special case.
export function localMidnight(
	year: number,
	month: number,
	day: number,
	timezone: string,
	now: Date = new Date()
) {
	const midnightAsIfUtc = Date.UTC(year, month - 1, day);
	const firstGuess = new Date(midnightAsIfUtc - offsetMilliseconds(now, timezone));
	return new Date(midnightAsIfUtc - offsetMilliseconds(firstGuess, timezone));
}

// The calendar day as three numbers, ready to be shifted and handed back to localMidnight.
export function calendarParts(value: Date, timezone: string) {
	const [year, month, day] = calendarDay(value, timezone).split('-').map(Number);
	return { year, month, day };
}

// Which day of the week that calendar day is, 0 for Sunday, in the organization's timezone. Worked out
// from the local date rather than from the instant, so late-evening UTC does not report tomorrow.
export function calendarWeekday(value: Date, timezone: string) {
	const { year, month, day } = calendarParts(value, timezone);
	return new Date(Date.UTC(year, month - 1, day)).getUTCDay();
}
