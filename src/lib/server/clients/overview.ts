import { calendarDay, calendarParts, localMidnight } from '$lib/server/time/calendar';

// The windows the Clients overview counts over, in the organization's own calendar. "Past 30 days" is
// the 30 calendar days ending today (today included), so on Oct 14 it runs Sep 15 – Oct 14; the 30 days
// before are the 30 calendar days ahead of that. "This year" starts at local midnight on January 1.
// The database is only handed the instants; the two calendar days ride along for the card's label.
export function clientOverviewWindows(timezone: string, now = new Date()) {
	const { year, month, day } = calendarParts(now, timezone);
	const currentSince = localMidnight(year, month, day - 29, timezone, now);
	const previousSince = localMidnight(year, month, day - 59, timezone, now);
	const yearSince = localMidnight(year, 1, 1, timezone, now);
	return {
		current_since: currentSince.toISOString(),
		previous_since: previousSince.toISOString(),
		year_since: yearSince.toISOString(),
		period: { from: calendarDay(currentSince, timezone), to: calendarDay(now, timezone) }
	};
}
