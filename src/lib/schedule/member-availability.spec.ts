import { describe, expect, it } from 'vitest';
import {
	availabilityOn,
	teamAvailability,
	type AvailabilityDayRow,
	type AvailabilityExceptionRow
} from '$lib/schedule/member-availability';

function day(overrides: Partial<AvailabilityDayRow> & { weekday: number }): AvailabilityDayRow {
	return {
		user_id: 'sam',
		is_working: true,
		starts_at: '08:00:00',
		ends_at: '16:30:00',
		...overrides
	};
}

function exception(
	overrides: Partial<AvailabilityExceptionRow> & { exception_date: string }
): AvailabilityExceptionRow {
	return {
		user_id: 'sam',
		is_working: false,
		starts_at: null,
		ends_at: null,
		...overrides
	};
}

// 2026-09-02 is a Wednesday, so weekday 3. 2026-09-05 is the Saturday of that week.
const WEDNESDAY = '2026-09-02';
const SATURDAY = '2026-09-05';

describe('teamAvailability', () => {
	it('keeps each person’s week and exceptions apart', () => {
		const team = teamAvailability(
			[day({ weekday: 3 }), day({ weekday: 3, user_id: 'ali', starts_at: '10:00:00' })],
			[exception({ exception_date: WEDNESDAY, user_id: 'ali' })]
		);

		expect(team.get('sam')?.week.get(3)).toEqual({ start: 480, end: 990 });
		expect(team.get('ali')?.week.get(3)).toEqual({ start: 600, end: 990 });
		expect(team.get('sam')?.exceptions.size).toBe(0);
		expect(team.get('ali')?.exceptions.get(WEDNESDAY)).toBeNull();
	});

	it('reads a day off as no band at all', () => {
		const team = teamAvailability(
			[day({ weekday: 6, is_working: false, starts_at: null, ends_at: null })],
			[]
		);
		expect(team.get('sam')?.week.get(6)).toBeNull();
	});

	// The database refuses to store this, so it only matters if a row ever arrives from somewhere else. It
	// is read as "not working" rather than silently becoming an all-day shift.
	it('treats a working day with unusable times as not working', () => {
		const team = teamAvailability(
			[day({ weekday: 1, starts_at: '17:00:00', ends_at: '09:00:00' })],
			[]
		);
		expect(team.get('sam')?.week.get(1)).toBeNull();
	});
});

describe('availabilityOn', () => {
	it('says nothing about someone with no pattern and no exception', () => {
		const team = teamAvailability([], []);
		expect(availabilityOn(team.get('sam'), WEDNESDAY)).toBeUndefined();
		expect(availabilityOn(undefined, WEDNESDAY)).toBeUndefined();
	});

	it('reads the weekly row for an ordinary day', () => {
		const team = teamAvailability([day({ weekday: 3 })], []);
		expect(availabilityOn(team.get('sam'), WEDNESDAY)).toEqual({ start: 480, end: 990 });
	});

	it('reads a day the week does not cover as unknown, not as a day off', () => {
		const team = teamAvailability([day({ weekday: 3 })], []);
		expect(availabilityOn(team.get('sam'), SATURDAY)).toBeUndefined();
	});

	it('lets a dated exception win over the weekly row', () => {
		const team = teamAvailability(
			[day({ weekday: 3 })],
			[exception({ exception_date: WEDNESDAY })]
		);
		expect(availabilityOn(team.get('sam'), WEDNESDAY)).toBeNull();
	});

	it('lets an exception give a day its own hours', () => {
		const team = teamAvailability(
			[day({ weekday: 3 })],
			[
				exception({
					exception_date: WEDNESDAY,
					is_working: true,
					starts_at: '10:00:00',
					ends_at: '14:00:00'
				})
			]
		);
		expect(availabilityOn(team.get('sam'), WEDNESDAY)).toEqual({ start: 600, end: 840 });
	});

	// Somebody with no ordinary week can still book a single day off, and that day is still an answer.
	it('honours an exception even when no weekly pattern exists', () => {
		const team = teamAvailability([], [exception({ exception_date: WEDNESDAY })]);
		expect(availabilityOn(team.get('sam'), WEDNESDAY)).toBeNull();
		expect(availabilityOn(team.get('sam'), SATURDAY)).toBeUndefined();
	});
});
