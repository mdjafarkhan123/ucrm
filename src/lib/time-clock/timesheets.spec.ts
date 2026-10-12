import { describe, expect, it } from 'vitest';
import {
	clockTime,
	dayTotals,
	entryPurpose,
	personName,
	readTimesheetFilters,
	shiftTimesheetDate,
	timesheetDays,
	timesheetFilterParams,
	timesheetRangeLabel,
	timesheetWarnings,
	visiblePeople,
	type TimesheetPerson
} from './timesheets';

const ANA = '11111111-1111-4111-8111-111111111111';
const BEN = '22222222-2222-4222-8222-222222222222';

function person(overrides: Partial<TimesheetPerson> = {}): TimesheetPerson {
	return {
		user_id: ANA,
		name: 'Ana Silva',
		avatar_url: null,
		status: 'active',
		is_me: false,
		days: {},
		total_minutes: 0,
		entry_count: 0,
		unapproved_count: 0,
		overlap_count: 0,
		running: null,
		...overrides
	};
}

const longRunning = {
	id: '44444444-4444-4444-8444-444444444444',
	kind: 'general',
	job_id: null,
	job_number: null,
	started_at: '2026-10-05T06:00:00Z',
	started_on: '2026-10-05',
	long_running: true,
	over_a_day: false,
	clocked_in: true
} as const;

describe('the Timesheets page remembers its filters in the URL', () => {
	it('opens on this week for everyone when the link is plain', () => {
		expect(readTimesheetFilters(new URLSearchParams())).toEqual({
			span: 'week',
			date: null,
			people: []
		});
		expect(timesheetFilterParams({ span: 'week', date: null, people: [] }).toString()).toBe('');
	});

	it('reads back exactly what it wrote', () => {
		const filters = { span: 'day', date: '2026-10-07', people: [ANA, BEN] } as const;
		const params = timesheetFilterParams({ ...filters, people: [...filters.people] });
		expect(params.get('view')).toBe('day');
		expect(readTimesheetFilters(params)).toEqual({ ...filters, people: [ANA, BEN] });
	});

	it('ignores a broken date, an unknown view, and anything that is not a person id', () => {
		const params = new URLSearchParams({
			view: 'month',
			date: '2026-02-30',
			people: `${ANA},not-an-id,${ANA},,${BEN}`
		});
		expect(readTimesheetFilters(params)).toEqual({ span: 'week', date: null, people: [ANA, BEN] });
		expect(readTimesheetFilters(new URLSearchParams({ date: '7 Oct' })).date).toBeNull();
	});
});

describe('moving through time', () => {
	it('steps a day in Day and a week in Week, across month and year ends', () => {
		expect(shiftTimesheetDate('2026-10-31', 'day', 1)).toBe('2026-11-01');
		expect(shiftTimesheetDate('2027-01-01', 'day', -1)).toBe('2026-12-31');
		expect(shiftTimesheetDate('2026-12-28', 'week', 1)).toBe('2027-01-04');
	});

	it('lists every day in the window, in order', () => {
		expect(timesheetDays({ from: '2026-10-04', to: '2026-10-10' })).toEqual([
			'2026-10-04',
			'2026-10-05',
			'2026-10-06',
			'2026-10-07',
			'2026-10-08',
			'2026-10-09',
			'2026-10-10'
		]);
		expect(timesheetDays({ from: '2026-10-07', to: '2026-10-07' })).toEqual(['2026-10-07']);
	});

	it('names the window as the Schedule does', () => {
		expect(timesheetRangeLabel('day', '2026-10-05', '2026-10-05')).toBe('Monday, October 5, 2026');
		expect(timesheetRangeLabel('week', '2026-10-04', '2026-10-10')).toBe('Oct 4 – Oct 10, 2026');
		expect(timesheetRangeLabel('week', '2026-12-27', '2027-01-02')).toBe(
			'Dec 27, 2026 – Jan 2, 2027'
		);
	});

	it('shows clock times in the business’s time zone, not the reader’s', () => {
		expect(clockTime('2026-10-05T12:00:00Z', 'America/New_York')).toBe('8:00 AM');
		expect(clockTime('2026-10-05T12:00:00Z', 'Asia/Dhaka')).toBe('6:00 PM');
	});
});

describe('what an entry was for', () => {
	const job = {
		id: 'job-1',
		number: 12,
		visible: true,
		closed: false,
		title: 'Spring cleanup',
		client_name: 'Lee'
	};

	it('names the Job with its title, or only its number when the reader may not open it', () => {
		expect(entryPurpose({ kind: 'job', job })).toBe('Job #12 · Spring cleanup');
		expect(
			entryPurpose({ kind: 'job', job: { ...job, visible: false, title: null, client_name: null } })
		).toBe('Job #12');
	});

	it('calls day-clock time and anything without a Job "General"', () => {
		expect(entryPurpose({ kind: 'general', job: null })).toBe('General');
		expect(entryPurpose({ kind: 'job', job: null })).toBe('General');
	});
});

describe('who is shown and their totals', () => {
	const ana = person({ days: { '2026-10-05': 480, '2026-10-06': 90 } });
	const ben = person({ user_id: BEN, name: null, days: { '2026-10-05': 30 } });

	it('shows everyone until people are chosen, then only them', () => {
		expect(visiblePeople([ana, ben], [])).toEqual([ana, ben]);
		expect(visiblePeople([ana, ben], [BEN])).toEqual([ben]);
		expect(visiblePeople([ana, ben], ['33333333-3333-4333-8333-333333333333'])).toEqual([]);
	});

	it('adds each day across the people shown, counting a missing day as nothing', () => {
		expect(dayTotals([ana, ben], ['2026-10-05', '2026-10-06', '2026-10-07'])).toEqual([510, 90, 0]);
		expect(dayTotals([], ['2026-10-05'])).toEqual([0]);
	});

	it('gives a person without a name a readable one', () => {
		expect(personName(ana)).toBe('Ana Silva');
		expect(personName(ben)).toBe('Unnamed team member');
	});
});

describe('what needs checking', () => {
	it('says nothing when all is well', () => {
		expect(timesheetWarnings([person(), person({ user_id: BEN })])).toEqual([]);
	});

	it('names one person, says "you" to the reader, and counts several', () => {
		expect(timesheetWarnings([person({ overlap_count: 2 })])).toEqual([
			'Ana Silva has entries that overlap.'
		]);
		expect(timesheetWarnings([person({ overlap_count: 1, is_me: true })])).toEqual([
			'You have entries that overlap.'
		]);
		expect(
			timesheetWarnings([person({ overlap_count: 1 }), person({ user_id: BEN, overlap_count: 3 })])
		).toEqual(['2 people have entries that overlap.']);
	});

	it('flags timers running over 12 hours, and lists overlaps first', () => {
		expect(timesheetWarnings([person({ running: longRunning })])).toEqual([
			"Ana Silva's timer has run over 12 hours."
		]);
		expect(timesheetWarnings([person({ running: longRunning, is_me: true })])).toEqual([
			'Your timer has run over 12 hours.'
		]);
		expect(
			timesheetWarnings([
				person({ running: longRunning, overlap_count: 1 }),
				person({ user_id: BEN, running: longRunning })
			])
		).toEqual(['Ana Silva has entries that overlap.', '2 timers have run over 12 hours.']);
	});

	it('does not flag a timer that is running but not yet long', () => {
		expect(
			timesheetWarnings([person({ running: { ...longRunning, long_running: false } })])
		).toEqual([]);
	});
});
