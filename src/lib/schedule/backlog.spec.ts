import { describe, expect, it } from 'vitest';
import { backlogAgeLabel, filterBacklog, waitingDays } from '$lib/schedule/backlog';
import type { UnscheduledVisit } from '$lib/schedule/api';

function visit(overrides: Partial<UnscheduledVisit> = {}): UnscheduledVisit {
	return {
		id: 'v1',
		job_id: 'j1',
		visit_date: null,
		start_time: null,
		end_time: null,
		all_day: false,
		title: null,
		completed_at: null,
		revision: 1,
		position: 0,
		created_at: '2026-09-01T10:00:00Z',
		assignee_ids: [],
		job_number: 7,
		job_title: 'Fence repair',
		client_id: 'c1',
		client_name: 'Acme Co',
		client_company_name: null,
		property_id: 'p1',
		property_label: 'North yard',
		property_address_line1: '12 Elm St',
		property_city: 'Springfield',
		property_state_region: 'IL',
		property_postal_code: '62701',
		...overrides
	};
}

describe('waitingDays', () => {
	it('is zero on the day it was created', () => {
		expect(waitingDays('2026-09-03', '2026-09-03')).toBe(0);
	});

	it('counts whole days regardless of timezone slide', () => {
		expect(waitingDays('2026-09-01', '2026-09-13')).toBe(12);
	});

	it('never goes negative when a clock skew puts creation in the future', () => {
		expect(waitingDays('2026-09-05', '2026-09-03')).toBe(0);
	});
});

describe('backlogAgeLabel', () => {
	it('says "Added today" for a fresh visit', () => {
		expect(backlogAgeLabel('2026-09-03', '2026-09-03')).toBe('Added today');
	});

	it('uses the singular for one day', () => {
		expect(backlogAgeLabel('2026-09-02', '2026-09-03')).toBe('Waiting 1 day');
	});

	it('uses the plural beyond one day', () => {
		expect(backlogAgeLabel('2026-08-24', '2026-09-03')).toBe('Waiting 10 days');
	});
});

describe('filterBacklog', () => {
	const rows = [
		visit({ id: 'a', client_name: 'Acme Co', assignee_ids: ['u1'] }),
		visit({ id: 'b', client_name: 'Bravo Ltd', job_title: 'Gutter clean', assignee_ids: [] }),
		visit({ id: 'c', client_name: 'Charlie', property_city: 'Riverside', assignee_ids: ['u2'] })
	];

	it('returns everything with an empty query and all employees', () => {
		expect(filterBacklog(rows, { query: '', employee: 'all' }).map((v) => v.id)).toEqual([
			'a',
			'b',
			'c'
		]);
	});

	it('matches the search against client, work and place', () => {
		expect(filterBacklog(rows, { query: 'gutter', employee: 'all' }).map((v) => v.id)).toEqual([
			'b'
		]);
		expect(filterBacklog(rows, { query: 'riverside', employee: 'all' }).map((v) => v.id)).toEqual([
			'c'
		]);
	});

	it('is case-insensitive and ignores surrounding spaces', () => {
		expect(filterBacklog(rows, { query: '  ACME ', employee: 'all' }).map((v) => v.id)).toEqual([
			'a'
		]);
	});

	it('narrows to one employee', () => {
		expect(filterBacklog(rows, { query: '', employee: 'u2' }).map((v) => v.id)).toEqual(['c']);
	});

	it('finds the unassigned pile', () => {
		expect(filterBacklog(rows, { query: '', employee: 'unassigned' }).map((v) => v.id)).toEqual([
			'b'
		]);
	});

	it('combines search and assignment', () => {
		expect(filterBacklog(rows, { query: 'charlie', employee: 'u1' })).toEqual([]);
	});
});
