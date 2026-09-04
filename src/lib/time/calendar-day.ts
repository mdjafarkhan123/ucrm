// Which calendar day an instant falls on, in a chosen timezone.
//
// It lives outside `$lib/server` because both sides of the app need the same answer: the server derives a
// request's status from it, and the Schedule in the browser needs to know which day is Today before it can
// say which visits are Late. One rule, so the two can never disagree by a day.

// en-CA gives YYYY-MM-DD, so two calendar days can be compared as plain strings.
export function calendarDay(value: Date, timezone: string) {
	return new Intl.DateTimeFormat('en-CA', {
		timeZone: timezone,
		year: 'numeric',
		month: '2-digit',
		day: '2-digit'
	}).format(value);
}

// The wall-clock time in a chosen timezone, as minutes past midnight. The calendar needs it to draw the
// current-time line where the contractor's own clock says it is, not where the browser's clock does.
export function clockMinutesInZone(value: Date, timezone: string) {
	const parts = new Intl.DateTimeFormat('en-GB', {
		timeZone: timezone,
		hour: '2-digit',
		minute: '2-digit',
		hourCycle: 'h23'
	}).formatToParts(value);
	const hour = Number(parts.find((part) => part.type === 'hour')?.value ?? '0');
	const minute = Number(parts.find((part) => part.type === 'minute')?.value ?? '0');
	return hour * 60 + minute;
}

// How far the timezone runs ahead of UTC at one particular instant. Read off the formatted local clock,
// because that is the only thing Intl will tell us, and the answer changes twice a year.
function offsetMilliseconds(at: Date, timezone: string) {
	const parts = new Intl.DateTimeFormat('en-US', {
		timeZone: timezone,
		year: 'numeric',
		month: '2-digit',
		day: '2-digit',
		hour: '2-digit',
		minute: '2-digit',
		second: '2-digit',
		hourCycle: 'h23'
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

// The reverse of calendarDay/clockMinutesInZone: a wall-clock day and time in a chosen timezone, turned
// back into the real instant it names. Booking forms read a day/time typed against the organization's own
// clock, not the browser's, so this is what a "Fri 4 Sept, 12:00 PM" the office typed has to go through
// before it becomes an instant Postgres can store.
//
// The offset is read twice: the first guess uses the offset happening now, the second uses the offset at
// the guessed instant itself, which is what fixes the two days a year when the clocks change in between.
export function zonedTimeToUtc(day: string, time: string, timezone: string): Date | null {
	const [year, month, date] = day.split('-').map(Number);
	const [hour, minute] = time.split(':').map(Number);
	if ([year, month, date, hour, minute].some((part) => Number.isNaN(part))) return null;

	const asIfUtc = Date.UTC(year, month - 1, date, hour, minute);
	const firstGuess = new Date(asIfUtc - offsetMilliseconds(new Date(), timezone));
	return new Date(asIfUtc - offsetMilliseconds(firstGuess, timezone));
}
