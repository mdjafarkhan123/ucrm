import { describe, expect, it } from 'vitest';
import {
	cardDensity,
	cardDensityForWidth,
	clockMinutes,
	DEFAULT_VISIT_MINUTES,
	layoutTimedVisits,
	splitDayVisits
} from '$lib/schedule/layout';
import type { ScheduleVisit } from '$lib/schedule/api';

function visit(overrides: Partial<ScheduleVisit> & { id: string }): ScheduleVisit {
	return {
		job_id: 'job-1',
		visit_date: '2026-09-02',
		start_time: '09:00:00',
		end_time: '11:00:00',
		all_day: false,
		title: null,
		completed_at: null,
		revision: 1,
		position: 0,
		assignee_ids: [],
		job_number: 1,
		job_title: 'Gutter clean',
		client_id: 'client-1',
		client_name: 'Dana Reed',
		client_company_name: null,
		property_id: 'property-1',
		property_label: null,
		property_address_line1: '4 Elm Street',
		property_city: 'Austin',
		property_state_region: 'TX',
		property_postal_code: '78701',
		...overrides
	};
}

/** The lane each visit landed in, keyed by id, plus how wide its group ended up. */
function lanes(blocks: ReturnType<typeof layoutTimedVisits>) {
	return Object.fromEntries(blocks.map((b) => [b.visit.id, `${b.column}/${b.columns}`]));
}

describe('clockMinutes', () => {
	it('reads a stored clock time as minutes from midnight', () => {
		expect(clockMinutes('14:30:00')).toBe(870);
		expect(clockMinutes('00:00:00')).toBe(0);
	});

	it('has no answer for a missing or unreadable time', () => {
		expect(clockMinutes(null)).toBeNull();
		expect(clockMinutes('Anytime')).toBeNull();
	});
});

describe('splitDayVisits', () => {
	it('sends a dated visit with no clock time to the Anytime lane', () => {
		const split = splitDayVisits([visit({ id: 'a', start_time: null, end_time: null })]);
		expect(split.anytime.map((v) => v.id)).toEqual(['a']);
		expect(split.timed).toHaveLength(0);
	});

	it('draws the default length when a visit has no end', () => {
		const split = splitDayVisits([visit({ id: 'a', start_time: '09:00:00', end_time: null })]);
		expect(split.timed[0]).toMatchObject({ start: 540, end: 540 + DEFAULT_VISIT_MINUTES });
	});

	it('draws the default length when the stored end is not after the start', () => {
		const split = splitDayVisits([
			visit({ id: 'a', start_time: '09:00:00', end_time: '08:00:00' })
		]);
		expect(split.timed[0].end).toBe(540 + DEFAULT_VISIT_MINUTES);
	});

	it('keeps a genuinely short visit at its true length', () => {
		const split = splitDayVisits([
			visit({ id: 'a', start_time: '09:00:00', end_time: '09:15:00' })
		]);
		expect(split.timed[0]).toMatchObject({ start: 540, end: 555 });
	});
});

describe('layoutTimedVisits', () => {
	it('gives a lone visit the whole column', () => {
		const { timed } = splitDayVisits([visit({ id: 'a' })]);
		expect(lanes(layoutTimedVisits(timed))).toEqual({ a: '0/1' });
	});

	it('splits the column between two visits that overlap', () => {
		const { timed } = splitDayVisits([
			visit({ id: 'a', start_time: '09:00:00', end_time: '11:00:00' }),
			visit({ id: 'b', start_time: '10:00:00', end_time: '12:00:00' })
		]);
		expect(lanes(layoutTimedVisits(timed))).toEqual({ a: '0/2', b: '1/2' });
	});

	it('gives back-to-back visits the full width each', () => {
		const { timed } = splitDayVisits([
			visit({ id: 'a', start_time: '09:00:00', end_time: '10:00:00' }),
			visit({ id: 'b', start_time: '10:00:00', end_time: '11:00:00' })
		]);
		expect(lanes(layoutTimedVisits(timed))).toEqual({ a: '0/1', b: '0/1' });
	});

	it('reuses a lane that has already finished inside the same group', () => {
		// a runs all morning; b and c follow each other, so they share the second lane and the group is
		// two wide rather than three.
		const { timed } = splitDayVisits([
			visit({ id: 'a', start_time: '09:00:00', end_time: '12:00:00' }),
			visit({ id: 'b', start_time: '09:30:00', end_time: '10:30:00' }),
			visit({ id: 'c', start_time: '10:30:00', end_time: '11:30:00' })
		]);
		expect(lanes(layoutTimedVisits(timed))).toEqual({ a: '0/2', b: '1/2', c: '1/2' });
	});

	it('keeps a later group at full width', () => {
		const { timed } = splitDayVisits([
			visit({ id: 'a', start_time: '09:00:00', end_time: '10:00:00' }),
			visit({ id: 'b', start_time: '09:00:00', end_time: '10:00:00' }),
			visit({ id: 'c', start_time: '14:00:00', end_time: '15:00:00' })
		]);
		expect(lanes(layoutTimedVisits(timed))).toEqual({ a: '0/2', b: '1/2', c: '0/1' });
	});

	it('returns every visit it was given', () => {
		const { timed } = splitDayVisits([
			visit({ id: 'a', start_time: '09:00:00', end_time: '17:00:00' }),
			visit({ id: 'b', start_time: '09:00:00', end_time: '17:00:00' }),
			visit({ id: 'c', start_time: '09:00:00', end_time: '17:00:00' })
		]);
		const blocks = layoutTimedVisits(timed);
		expect(blocks).toHaveLength(3);
		expect(new Set(blocks.map((b) => b.column))).toEqual(new Set([0, 1, 2]));
	});
});

describe('cardDensity', () => {
	it('drops a very short block to the smallest form', () => {
		expect(cardDensity(24, 1)).toBe('micro');
	});

	it('drops a crowded hour to the smallest form however tall it is', () => {
		expect(cardDensity(200, 4)).toBe('micro');
	});

	it('uses the compact form when a block shares its hour', () => {
		expect(cardDensity(200, 2)).toBe('compact');
	});

	it('uses the full form only when the block has the column to itself', () => {
		expect(cardDensity(96, 1)).toBe('standard');
	});
});

describe('cardDensityForWidth', () => {
	it('drops a quarter-hour sliver to the smallest form', () => {
		expect(cardDensityForWidth(30)).toBe('micro');
	});

	it('uses the compact form for a short visit', () => {
		expect(cardDensityForWidth(120)).toBe('compact');
	});

	it('uses the full form once the block is genuinely wide', () => {
		expect(cardDensityForWidth(240)).toBe('standard');
	});
});
