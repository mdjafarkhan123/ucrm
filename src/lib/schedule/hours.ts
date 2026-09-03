import type { ScheduleContext } from '$lib/schedule/api';
import { clockMinutes, MINUTES_IN_DAY } from '$lib/schedule/layout';

// The working part of each weekday, ready for the grid to shade.
//
// The calendar never guesses these. When the business has not set a weekly pattern there is nothing honest
// to shade, so this says so rather than inventing nine to five.

/** Minutes from midnight. */
export type WorkingBand = { start: number; end: number };

/** 0 is Sunday, matching both the Business Hours screen and `Date#getUTCDay`. */
export type WorkingWeek = Map<number, WorkingBand[]>;

// Null when the contractor has no confirmed weekly pattern -- not configured, or open by appointment only.
export function workingWeek(
	context: Pick<ScheduleContext, 'hours_mode' | 'hours'>
): WorkingWeek | null {
	if (context.hours_mode !== 'weekly') return null;

	const week: WorkingWeek = new Map();
	for (const period of context.hours) {
		if (!period.is_open) continue;
		const band = period.is_open_24h
			? { start: 0, end: MINUTES_IN_DAY }
			: bandFrom(period.opens_at, period.closes_at);
		if (!band) continue;
		const bands = week.get(period.weekday);
		if (bands) bands.push(band);
		else week.set(period.weekday, [band]);
	}

	// A weekday can hold several rows -- a business that closes for lunch has two. Overlapping ones are
	// merged so the grid tints each minute once instead of stacking two washes on the same hour.
	for (const [weekday, bands] of week) week.set(weekday, mergeBands(bands));
	return week.size > 0 ? week : null;
}

function bandFrom(opensAt: string | null, closesAt: string | null): WorkingBand | null {
	const start = clockMinutes(opensAt);
	const end = clockMinutes(closesAt);
	if (start === null || end === null) return null;
	// A closing time at or before opening is a row the grid cannot draw. It is skipped rather than shaded
	// backwards or stretched to midnight.
	return end > start ? { start, end } : null;
}

function mergeBands(bands: WorkingBand[]): WorkingBand[] {
	const sorted = [...bands].sort((a, b) => a.start - b.start || a.end - b.end);
	const merged: WorkingBand[] = [];
	for (const band of sorted) {
		const last = merged[merged.length - 1];
		if (last && band.start <= last.end) last.end = Math.max(last.end, band.end);
		else merged.push({ ...band });
	}
	return merged;
}

/** Which weekday a plain YYYY-MM-DD day is. Read in UTC so the day cannot slide for a western browser. */
export function weekdayOf(day: string): number {
	return new Date(`${day}T00:00:00Z`).getUTCDay();
}

/** The earliest minute the business opens anywhere in the week, for deciding where the grid opens scrolled. */
export function earliestWorkingMinute(week: WorkingWeek | null): number | null {
	if (!week) return null;
	let earliest: number | null = null;
	for (const bands of week.values()) {
		for (const band of bands) {
			if (earliest === null || band.start < earliest) earliest = band.start;
		}
	}
	return earliest;
}
