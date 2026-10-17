import { describe, expect, it } from 'vitest';
import { monthComparison, percentChange } from './money';
import { buildHomeSchedule, clockTile } from './schedule';
import { buildTodoColumns } from './todo';
import type { ScheduleVisit, ScheduleWindowPage } from '$lib/schedule/api';

describe('monthComparison', () => {
	it('compares this month so far with last month to the same day', () => {
		const result = monthComparison('2026-10-14');
		expect(result.current).toEqual({ from: '2026-10-01', to: '2026-10-15' });
		expect(result.previous).toEqual({ from: '2026-09-01', to: '2026-09-15' });
		expect(result.currentLabel).toBe('Oct 1–14');
		expect(result.previousLabel).toBe('Sep 1–14');
	});
	it('compares the whole of a shorter last month on the 31st', () => {
		const result = monthComparison('2026-10-31');
		expect(result.previous).toEqual({ from: '2026-09-01', to: '2026-10-01' });
		expect(result.previousLabel).toBe('Sep 1–30');
	});
	it('crosses the year', () => {
		expect(monthComparison('2027-01-05').previous.from).toBe('2026-12-01');
	});
});

describe('percentChange', () => {
	it('rounds and signs the change', () => {
		expect(percentChange(112, 100)).toBe(12);
		expect(percentChange(94, 100)).toBe(-6);
	});
	it('has no answer without a previous figure', () => {
		expect(percentChange(50, 0)).toBeNull();
	});
});

describe('buildTodoColumns', () => {
	it('sums each column and leaves out areas the person cannot see', () => {
		const columns = buildTodoColumns(
			{ requests: true, quotes: false, jobs: false, invoices: true },
			{
				requests: { counts: { needs_approval: 2, new: 5, assessment_completed: 1 } as never },
				invoices: {
					counts: { draft: 2, awaiting_payment: 9, past_due: 5 } as never,
					outstanding_minor: 100_00,
					overdue_minor: 30_00,
					collected_this_month_minor: 0,
					currency_code: 'USD',
					locale: 'en-US',
					facts: {
						paid_count: 0,
						average_days_to_paid: null,
						overdue_reminders_on: false,
						overdue_reminder_days_after_due: null
					}
				}
			}
		);
		expect(columns.map((column) => column.key)).toEqual(['requests', 'invoices']);
		expect(columns[0].total).toBe(8);
		expect(columns[1].total).toBe(16);
		expect(columns[1].lines[1].valueMinor).toBe(70_00);
		expect(columns[1].lines[2].valueMinor).toBe(30_00);
	});
	it('keeps counts null while an overview is still loading', () => {
		const [column] = buildTodoColumns(
			{ requests: true, quotes: false, jobs: false, invoices: false },
			{}
		);
		expect(column.total).toBeNull();
	});
});

function visit(overrides: Partial<ScheduleVisit>): ScheduleVisit {
	return {
		id: 'v',
		job_id: 'j',
		visit_date: '2026-10-14',
		start_time: '08:00:00',
		end_time: '16:00:00',
		all_day: false,
		title: null,
		completed_at: null,
		revision: 1,
		position: 0,
		assignee_ids: ['a'],
		job_number: 1,
		job_title: 'Decking install',
		client_id: 'c',
		client_name: 'Sarah Mitchell',
		client_company_name: null,
		property_id: 'p',
		property_label: null,
		property_address_line1: '1428 Cedar Ridge Dr',
		property_city: 'Burnaby',
		property_state_region: null,
		property_postal_code: null,
		property_latitude: null,
		property_longitude: null,
		property_geocode_status: null,
		...overrides
	};
}

describe('buildHomeSchedule', () => {
	const page = (visits: ScheduleVisit[]): ScheduleWindowPage => ({
		from: '2026-09-30',
		to: '2026-10-14',
		visits,
		assessments: [],
		events: [],
		truncated: false,
		limit: 400,
		scope: 'all'
	});

	it('puts late work first, today in time order and anytime work last', () => {
		const result = buildHomeSchedule(
			page([
				visit({ id: 'any', start_time: null, end_time: null }),
				visit({ id: 'late', visit_date: '2026-10-12' }),
				visit({ id: 'noon', start_time: '12:00:00', end_time: '13:30:00' }),
				visit({ id: 'early', start_time: '07:30:00', end_time: '08:30:00', completed_at: 'x' }),
				visit({ id: 'old-done', visit_date: '2026-10-10', completed_at: 'x' }),
				visit({ id: 'future', visit_date: '2026-10-15' })
			]),
			'America/Vancouver',
			'2026-10-14'
		);
		expect(result.late.map((row) => row.key)).toEqual(['visit:late']);
		expect(result.late[0].timeTop).toBe('12');
		expect(result.late[0].timeBottom).toBe('MON');
		expect(result.today.map((row) => row.key)).toEqual(['visit:early', 'visit:noon', 'visit:any']);
		expect(result.today[1].length).toBe('1.5 hr');
		expect(result.today[2].timeTop).toBe('ANY');
		expect(result.counts).toMatchObject({ total: 3, completed: 1, todo: 2, late: 1, unassigned: 0 });
		expect(result.lastEndMinutes).toBe(13.5 * 60);
	});

	it('counts unassigned work and people out', () => {
		const result = buildHomeSchedule(
			page([visit({ id: 'a1' }), visit({ id: 'a2', assignee_ids: [] })]),
			'UTC',
			'2026-10-14'
		);
		expect(result.counts.unassigned).toBe(1);
		expect(result.peopleOut).toBe(1);
		expect(result.byPerson.at(-1)?.id).toBeNull();
	});

	it('writes clock tiles in twelve-hour time', () => {
		expect(clockTile(13 * 60)).toEqual({ top: '1:00', bottom: 'PM' });
		expect(clockTile(0)).toEqual({ top: '12:00', bottom: 'AM' });
	});
});
