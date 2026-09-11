import { clockMinutes } from '$lib/schedule/layout';
import { weekdayOf, type WorkingBand } from '$lib/schedule/hours';

// When each person can work, in the shape the calendar asks about it.
//
// This is the per-person twin of $lib/schedule/hours, and it answers a narrower question: on this date, is
// this employee working, and between which hours? The two are deliberately separate. Business Hours say when
// the company operates and warn about the slot; availability says when one person works and warns about that
// person. A visit at 7pm on a Saturday can be both.
//
// Nothing here is a rule. The Schedule uses it to say "you should know" before a save, never to refuse one --
// "Availability guides scheduling rather than blocking it."

/** Null means the person is not working that day at all. */
export type DayAvailability = WorkingBand | null;

export type MemberAvailability = {
	/** 0 is Sunday, matching weekdayOf and the Business Hours screen. Empty means no pattern was ever set. */
	week: Map<number, DayAvailability>;
	/** Keyed by YYYY-MM-DD. An entry wins over the weekly row for that date. */
	exceptions: Map<string, DayAvailability>;
};

export type TeamAvailability = Map<string, MemberAvailability>;

/** One weekly row as the API sends it. */
export type AvailabilityDayRow = {
	user_id: string;
	weekday: number;
	is_working: boolean;
	starts_at: string | null;
	ends_at: string | null;
};

/** One dated override as the API sends it. */
export type AvailabilityExceptionRow = {
	user_id: string;
	exception_date: string;
	is_working: boolean;
	starts_at: string | null;
	ends_at: string | null;
};

export function teamAvailability(
	days: AvailabilityDayRow[],
	exceptions: AvailabilityExceptionRow[]
): TeamAvailability {
	const team: TeamAvailability = new Map();

	const forMember = (userId: string): MemberAvailability => {
		const existing = team.get(userId);
		if (existing) return existing;
		const created: MemberAvailability = { week: new Map(), exceptions: new Map() };
		team.set(userId, created);
		return created;
	};

	for (const day of days) {
		forMember(day.user_id).week.set(
			day.weekday,
			bandFrom(day.is_working, day.starts_at, day.ends_at)
		);
	}
	for (const entry of exceptions) {
		forMember(entry.user_id).exceptions.set(
			entry.exception_date,
			bandFrom(entry.is_working, entry.starts_at, entry.ends_at)
		);
	}

	return team;
}

// A row that claims to be a working day without usable times is treated as not working rather than as an
// all-day shift. The database's band constraint already refuses to store one, so this only matters if a row
// ever arrives from somewhere else.
function bandFrom(
	isWorking: boolean,
	startsAt: string | null,
	endsAt: string | null
): DayAvailability {
	if (!isWorking) return null;
	const start = clockMinutes(startsAt);
	const end = clockMinutes(endsAt);
	if (start === null || end === null || end <= start) return null;
	return { start, end };
}

/**
 * What one person's availability says about one date, or undefined when nobody has said anything -- no
 * weekly pattern and no exception for that day. Undefined is not "unavailable"; it is "unknown", and an
 * unknown never produces a warning.
 */
export function availabilityOn(
	availability: MemberAvailability | undefined,
	day: string
): DayAvailability | undefined {
	if (!availability) return undefined;

	// An exception is an answer for that date even when it is "day off", so it is checked before the week.
	if (availability.exceptions.has(day)) return availability.exceptions.get(day) ?? null;

	// has(), not get() ?? undefined: a stored day off is null, and null is a real answer. Collapsing it into
	// undefined would quietly turn "Sam does not work Saturdays" back into "nobody has said", and the
	// Saturday warning would never appear.
	const weekday = weekdayOf(day);
	if (!availability.week.has(weekday)) return undefined;
	return availability.week.get(weekday) ?? null;
}
