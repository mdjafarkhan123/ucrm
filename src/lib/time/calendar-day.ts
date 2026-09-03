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
