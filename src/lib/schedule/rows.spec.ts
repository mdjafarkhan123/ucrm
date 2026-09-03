import { describe, expect, it } from 'vitest';
import { buildDayRows } from '$lib/schedule/rows';
import type { ScheduleVisit } from '$lib/schedule/api';
import type { TeamMember } from '$lib/team/api';

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

function member(id: string, full_name: string): TeamMember {
	return { id, full_name, avatar_url: null, schedule_color: null };
}

const team = [member('sam', 'Sam Ortiz'), member('mia', 'Mia Chen')];

describe('buildDayRows', () => {
	it('puts unassigned first and keeps a row for an employee with an empty day', () => {
		const rows = buildDayRows([visit({ id: 'a' })], team, 'all');
		expect(rows.map((row) => row.key)).toEqual(['unassigned', 'sam', 'mia']);
		expect(rows[0].count).toBe(1);
		expect(rows[1].count).toBe(0);
		expect(rows[1].lanes).toBe(1);
	});

	it('draws a shared visit in every assigned row as the same visit', () => {
		const rows = buildDayRows([visit({ id: 'a', assignee_ids: ['sam', 'mia'] })], team, 'all');
		const sam = rows.find((row) => row.key === 'sam');
		const mia = rows.find((row) => row.key === 'mia');
		expect(sam?.blocks[0].visit.id).toBe('a');
		expect(mia?.blocks[0].visit.id).toBe('a');
		expect(rows.find((row) => row.key === 'unassigned')?.count).toBe(0);
	});

	it('keeps a dated visit with no clock time out of the time axis', () => {
		const rows = buildDayRows(
			[visit({ id: 'a', start_time: null, end_time: null, assignee_ids: ['sam'] })],
			team,
			'all'
		);
		const sam = rows.find((row) => row.key === 'sam');
		expect(sam?.anytime.map((v) => v.id)).toEqual(['a']);
		expect(sam?.blocks).toHaveLength(0);
		expect(sam?.count).toBe(1);
	});

	it('grows a row to as many lanes as its busiest moment stacks', () => {
		const rows = buildDayRows(
			[
				visit({ id: 'a', assignee_ids: ['sam'] }),
				visit({ id: 'b', assignee_ids: ['sam'], start_time: '10:00:00', end_time: '12:00:00' }),
				visit({ id: 'c', assignee_ids: ['sam'], start_time: '14:00:00', end_time: '15:00:00' })
			],
			team,
			'all'
		);
		expect(rows.find((row) => row.key === 'sam')?.lanes).toBe(2);
	});

	it('shows only the row that was filtered to', () => {
		const rows = buildDayRows([visit({ id: 'a', assignee_ids: ['mia'] })], team, 'mia');
		expect(rows.map((row) => row.key)).toEqual(['mia']);
	});

	it('shows only the unassigned pile when the filter asks for it', () => {
		const rows = buildDayRows([visit({ id: 'a' })], team, 'unassigned');
		expect(rows.map((row) => row.key)).toEqual(['unassigned']);
	});

	it('gives an assignee who is not on the roster their own row rather than dropping the visit', () => {
		const rows = buildDayRows([visit({ id: 'a', assignee_ids: ['gone'] })], team, 'all');
		const stray = rows.find((row) => row.key === 'gone');
		expect(stray?.name).toBe('Unlisted team member');
		expect(stray?.count).toBe(1);
		expect(rows.map((row) => row.key)).toEqual(['unassigned', 'sam', 'mia', 'gone']);
	});
});
