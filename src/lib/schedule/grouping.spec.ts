import { describe, expect, it } from 'vitest';
import { filterVisits, orderDayVisits } from '$lib/schedule/grouping';
import type { ScheduleVisit } from '$lib/schedule/api';
import type { VisitItem } from '$lib/schedule/items';

const TODAY = '2026-09-02';
const ANA = '11111111-1111-1111-1111-111111111111';
const BEN = '22222222-2222-2222-2222-222222222222';

function visit(overrides: Partial<ScheduleVisit> & { id: string }): VisitItem {
	return {
		kind: 'visit',
		job_id: 'job-1',
		visit_date: TODAY,
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
		property_latitude: null,
		property_longitude: null,
		property_geocode_status: 'pending',
		...overrides
	};
}

describe('filterVisits', () => {
	const visits = [
		visit({ id: 'a', assignee_ids: [ANA] }),
		visit({ id: 'b', assignee_ids: [ANA, BEN] }),
		visit({ id: 'c', assignee_ids: [] }),
		visit({ id: 'd', assignee_ids: [BEN], visit_date: '2026-09-01' })
	];
	const every = { employee: 'all' as const, status: 'all' as const };

	it('keeps everything when nothing is filtered', () => {
		expect(filterVisits(visits, every, TODAY)).toHaveLength(4);
	});

	it('finds a shared visit under either of its employees', () => {
		expect(filterVisits(visits, { ...every, employee: ANA }, TODAY).map((v) => v.id)).toEqual([
			'a',
			'b'
		]);
		expect(filterVisits(visits, { ...every, employee: BEN }, TODAY).map((v) => v.id)).toEqual([
			'b',
			'd'
		]);
	});

	it('shows only visits nobody is on under Unassigned', () => {
		expect(
			filterVisits(visits, { ...every, employee: 'unassigned' }, TODAY).map((v) => v.id)
		).toEqual(['c']);
	});

	it('filters by the status the visit derives, not a stored one', () => {
		expect(filterVisits(visits, { ...every, status: 'late' }, TODAY).map((v) => v.id)).toEqual([
			'd'
		]);
		expect(filterVisits(visits, { ...every, status: 'today' }, TODAY)).toHaveLength(3);
	});

	it('applies employee and status together', () => {
		expect(filterVisits(visits, { employee: BEN, status: 'late' }, TODAY).map((v) => v.id)).toEqual(
			['d']
		);
	});
});

describe('orderDayVisits', () => {
	it('puts anytime work first, then the timed work in start order', () => {
		const ordered = orderDayVisits([
			visit({ id: 'noon', start_time: '12:00:00' }),
			visit({ id: 'anytime', start_time: null }),
			visit({ id: 'dawn', start_time: '07:30:00' })
		]);
		expect(ordered.map((v) => v.id)).toEqual(['anytime', 'dawn', 'noon']);
	});

	it('keeps two visits that start at the same minute in a stable order', () => {
		const clash = [
			visit({ id: 'b', start_time: '09:00:00' }),
			visit({ id: 'a', start_time: '09:00:00' })
		];
		expect(orderDayVisits(clash).map((v) => v.id)).toEqual(['a', 'b']);
		expect(orderDayVisits([...clash].reverse()).map((v) => v.id)).toEqual(['a', 'b']);
	});

	it('gives nothing back for a day with nothing on it', () => {
		expect(orderDayVisits([])).toEqual([]);
	});
});
