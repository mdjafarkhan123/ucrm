import { describe, expect, it } from 'vitest';
import {
	canApplyToFuture,
	canDragVisit,
	describeChange,
	draftAnytime,
	draftFromClick,
	draftFromRange,
	formatClock,
	futureScopeFields,
	MIN_VISIT_MINUTES,
	minutesFromOffset,
	proposeAssignment,
	proposeMove,
	proposeResize,
	shiftDay,
	snapMinutes,
	toProposal,
	visitDurationMinutes,
	type VisitSchedule
} from '$lib/schedule/drag';

function schedule(overrides: Partial<VisitSchedule> = {}): VisitSchedule {
	return {
		visit_date: '2026-09-02',
		start_time: '09:00:00',
		end_time: '11:00:00',
		all_day: false,
		assignee_ids: ['sam'],
		...overrides
	};
}

describe('snapMinutes', () => {
	it('rounds to the nearest quarter hour', () => {
		expect(snapMinutes(0)).toBe(0);
		expect(snapMinutes(7)).toBe(0);
		expect(snapMinutes(8)).toBe(15);
		expect(snapMinutes(521)).toBe(525);
	});

	it('never leaves the day', () => {
		expect(snapMinutes(-40)).toBe(0);
		expect(snapMinutes(5000)).toBe(1440);
	});
});

describe('minutesFromOffset', () => {
	it('reads a pointer position through the grid scale', () => {
		// 48px an hour is 0.8px a minute: 200px down is 250 minutes, snapped to 255.
		expect(minutesFromOffset(200, 48 / 60)).toBe(255);
	});

	it('answers zero for a scale that cannot be measured', () => {
		expect(minutesFromOffset(200, 0)).toBe(0);
		expect(minutesFromOffset(200, Number.NaN)).toBe(0);
	});
});

describe('formatClock', () => {
	it('writes the wire format, without seconds', () => {
		expect(formatClock(0)).toBe('00:00');
		expect(formatClock(870)).toBe('14:30');
		expect(formatClock(1439)).toBe('23:59');
	});
});

describe('visitDurationMinutes', () => {
	it('measures a real span', () => {
		expect(visitDurationMinutes(schedule())).toBe(120);
	});

	it('reads a missing or backwards end as the default hour, the way the grid draws it', () => {
		expect(visitDurationMinutes(schedule({ end_time: null }))).toBe(60);
		expect(visitDurationMinutes(schedule({ end_time: '08:00:00' }))).toBe(60);
		expect(visitDurationMinutes(schedule({ start_time: null }))).toBe(60);
	});
});

describe('proposeMove', () => {
	it('carries the duration to the new slot', () => {
		const proposal = proposeMove(schedule(), { day: '2026-09-04', startMinutes: 840 });
		expect(proposal).toEqual({
			visit_date: '2026-09-04',
			start_time: '14:00',
			end_time: '16:00',
			all_day: false,
			assignee_ids: ['sam']
		});
	});

	it('snaps the drop point', () => {
		const proposal = proposeMove(schedule(), { day: '2026-09-02', startMinutes: 848 });
		expect(proposal.start_time).toBe('14:15');
	});

	it('pulls a late drop back so the visit still ends inside the day', () => {
		const proposal = proposeMove(schedule(), { day: '2026-09-02', startMinutes: 1425 });
		expect(proposal.start_time).toBe('22:00');
		expect(proposal.end_time).toBe('23:59');
	});

	it('drops the clock time for the Anytime lane and keeps the day', () => {
		const proposal = proposeMove(schedule(), { day: '2026-09-05', startMinutes: null });
		expect(proposal).toEqual({
			visit_date: '2026-09-05',
			start_time: null,
			end_time: null,
			all_day: true,
			assignee_ids: ['sam']
		});
	});

	it('gives an Anytime visit the default hour when it lands on the time axis', () => {
		const anytime = schedule({ start_time: null, end_time: null, all_day: true });
		const proposal = proposeMove(anytime, { day: '2026-09-02', startMinutes: 480 });
		expect(proposal.start_time).toBe('08:00');
		expect(proposal.end_time).toBe('09:00');
		expect(proposal.all_day).toBe(false);
	});

	it('replaces the crew only when the drop crossed employee rows', () => {
		expect(proposeMove(schedule(), { day: '2026-09-02', startMinutes: 540 }).assignee_ids).toEqual([
			'sam'
		]);
		expect(
			proposeMove(schedule(), { day: '2026-09-02', startMinutes: 540, assigneeIds: ['ana'] })
				.assignee_ids
		).toEqual(['ana']);
	});
});

describe('proposeResize', () => {
	it('moves the end and leaves the start alone', () => {
		const proposal = proposeResize(schedule(), 750);
		expect(proposal.start_time).toBe('09:00');
		expect(proposal.end_time).toBe('12:30');
	});

	it('refuses to squash a visit below a quarter hour', () => {
		const proposal = proposeResize(schedule(), 300);
		expect(proposal.end_time).toBe(formatClock(540 + MIN_VISIT_MINUTES));
	});

	it('leaves an Anytime visit alone, because it has no edge to drag', () => {
		const anytime = schedule({ start_time: null, end_time: null, all_day: true });
		expect(proposeResize(anytime, 600)).toEqual(toProposal(anytime));
	});
});

describe('describeChange', () => {
	it('sees nothing when the drag put everything back', () => {
		const change = describeChange(schedule(), toProposal(schedule()));
		expect(change.changed).toBe(false);
	});

	it('separates a date move from a time move', () => {
		const moved = describeChange(
			schedule(),
			proposeMove(schedule(), {
				day: '2026-09-04',
				startMinutes: 540
			})
		);
		expect(moved.date).toBe(true);
		expect(moved.time).toBe(false);

		const retimed = describeChange(
			schedule(),
			proposeMove(schedule(), {
				day: '2026-09-02',
				startMinutes: 600
			})
		);
		expect(retimed.date).toBe(false);
		expect(retimed.time).toBe(true);
	});

	it('names a resize a duration change', () => {
		const change = describeChange(schedule(), proposeResize(schedule(), 720));
		expect(change.duration).toBe(true);
		expect(change.time).toBe(false);
	});

	it('names both directions of the shape change', () => {
		const anytime = schedule({ start_time: null, end_time: null, all_day: true });
		expect(describeChange(schedule(), toProposal(anytime)).shape).toBe('to_anytime');
		expect(describeChange(anytime, toProposal(schedule())).shape).toBe('to_timed');
	});

	it('sees a crew change however the ids are ordered', () => {
		const crew = schedule({ assignee_ids: ['sam', 'ana'] });
		expect(describeChange(crew, proposeAssignment(crew, ['ana', 'sam'])).assignment).toBe(false);
		expect(describeChange(crew, proposeAssignment(crew, ['ana'])).assignment).toBe(true);
	});
});

describe('futureScopeFields', () => {
	it('carries a new time of day forward', () => {
		const change = describeChange(
			schedule(),
			proposeMove(schedule(), {
				day: '2026-09-02',
				startMinutes: 600
			})
		);
		expect(futureScopeFields(change)).toEqual({ time_of_day: true, assigned_team: false });
	});

	it('carries a new crew forward', () => {
		const change = describeChange(schedule(), proposeAssignment(schedule(), ['ana']));
		expect(futureScopeFields(change)).toEqual({ time_of_day: false, assigned_team: true });
	});

	it('keeps a date move to this visit alone, as the contract requires', () => {
		const change = describeChange(
			schedule(),
			proposeMove(schedule(), {
				day: '2026-09-09',
				startMinutes: 540
			})
		);
		expect(canApplyToFuture(change)).toBe(false);
	});

	it('keeps a shape change to this visit alone, because the command cannot carry it', () => {
		const change = describeChange(
			schedule(),
			proposeMove(schedule(), {
				day: '2026-09-02',
				startMinutes: null
			})
		);
		expect(canApplyToFuture(change)).toBe(false);
	});
});

describe('canDragVisit', () => {
	it('refuses a completed visit and a reader who may not schedule', () => {
		expect(canDragVisit({ completed_at: null }, true)).toBe(true);
		expect(canDragVisit({ completed_at: '2026-09-01T10:00:00Z' }, true)).toBe(false);
		expect(canDragVisit({ completed_at: null }, false)).toBe(false);
	});
});

describe('shiftDay', () => {
	it('steps whole days across a month end', () => {
		expect(shiftDay('2026-09-30', 1)).toBe('2026-10-01');
		expect(shiftDay('2026-09-01', -1)).toBe('2026-08-31');
	});
});

describe('draftFromClick', () => {
	it('opens a one-hour visit snapped to the quarter hour', () => {
		expect(draftFromClick('2026-09-02', 9 * 60 + 7)).toEqual({
			visit_date: '2026-09-02',
			start_time: '09:00',
			end_time: '10:00',
			all_day: false
		});
	});

	it('pulls the hour back so it never runs past midnight', () => {
		expect(draftFromClick('2026-09-02', 23 * 60 + 40)).toEqual({
			visit_date: '2026-09-02',
			start_time: '23:00',
			end_time: '23:59',
			all_day: false
		});
	});
});

describe('draftFromRange', () => {
	it('prefills exactly the block that was drawn, in either direction', () => {
		const forward = draftFromRange('2026-09-02', 9 * 60, 11 * 60);
		const backward = draftFromRange('2026-09-02', 11 * 60, 9 * 60);
		expect(forward).toEqual({
			visit_date: '2026-09-02',
			start_time: '09:00',
			end_time: '11:00',
			all_day: false
		});
		expect(backward).toEqual(forward);
	});

	it('falls back to the one-hour default when the drag is too short to be a block', () => {
		expect(draftFromRange('2026-09-02', 9 * 60, 9 * 60 + 5)).toEqual(
			draftFromClick('2026-09-02', 9 * 60)
		);
	});
});

describe('draftAnytime', () => {
	it('starts a date-only visit with no clock time', () => {
		expect(draftAnytime('2026-09-02')).toEqual({
			visit_date: '2026-09-02',
			start_time: null,
			end_time: null,
			all_day: true
		});
	});
});
