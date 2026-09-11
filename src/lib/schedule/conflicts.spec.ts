import { describe, expect, it } from 'vitest';
import { scheduleWarnings } from '$lib/schedule/conflicts';
import type { ScheduleProposal } from '$lib/schedule/drag';
import { workingWeek } from '$lib/schedule/hours';
import { teamAvailability } from '$lib/schedule/member-availability';
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
		assignee_ids: ['sam'],
		job_number: 1,
		job_title: 'Gutter clean',
		client_id: 'client-1',
		client_name: 'Dana Reed',
		client_company_name: null,
		property_id: 'property-1',
		property_label: null,
		property_address_line1: null,
		property_city: null,
		property_state_region: null,
		property_postal_code: null,
		property_latitude: null,
		property_longitude: null,
		property_geocode_status: 'pending',
		...overrides
	};
}

function proposal(overrides: Partial<ScheduleProposal> = {}): ScheduleProposal {
	return {
		visit_date: '2026-09-02',
		start_time: '10:00',
		end_time: '12:00',
		all_day: false,
		assignee_ids: ['sam'],
		...overrides
	};
}

// 2026-09-02 is a Wednesday, weekday 3. Open nine to five, closed at the weekend.
const weekdayHours = workingWeek({
	hours_mode: 'weekly',
	hours: [1, 2, 3, 4, 5].map((weekday) => ({
		weekday,
		period_index: 0,
		is_open: true,
		is_open_24h: false,
		opens_at: '09:00:00',
		closes_at: '17:00:00'
	}))
});

describe('scheduleWarnings — overlaps', () => {
	it('warns when the same employee is already booked across the slot', () => {
		const warnings = scheduleWarnings({
			visitId: 'moving',
			proposal: proposal(),
			visits: [visit({ id: 'other' })],
			workingWeek: null
		});
		expect(warnings).toEqual([{ kind: 'overlap', employee_id: 'sam', visit_ids: ['other'] }]);
	});

	it('does not warn about the visit being moved', () => {
		const warnings = scheduleWarnings({
			visitId: 'moving',
			proposal: proposal(),
			visits: [visit({ id: 'moving' })],
			workingWeek: null
		});
		expect(warnings).toEqual([]);
	});

	it('does not warn about a different employee, a different day, or completed work', () => {
		const warnings = scheduleWarnings({
			visitId: 'moving',
			proposal: proposal(),
			visits: [
				visit({ id: 'other-crew', assignee_ids: ['ana'] }),
				visit({ id: 'other-day', visit_date: '2026-09-03' }),
				visit({ id: 'done', completed_at: '2026-09-02T10:00:00Z' })
			],
			workingWeek: null
		});
		expect(warnings).toEqual([]);
	});

	it('treats touching ends as a full day, not a clash', () => {
		const warnings = scheduleWarnings({
			visitId: 'moving',
			proposal: proposal({ start_time: '11:00', end_time: '12:00' }),
			visits: [visit({ id: 'earlier', start_time: '09:00:00', end_time: '11:00:00' })],
			workingWeek: null
		});
		expect(warnings).toEqual([]);
	});

	it('never overlaps an Anytime proposal, which claims no hour', () => {
		const warnings = scheduleWarnings({
			visitId: 'moving',
			proposal: proposal({ start_time: null, end_time: null, all_day: true }),
			visits: [visit({ id: 'other' })],
			workingWeek: null
		});
		expect(warnings).toEqual([]);
	});

	it('gives one warning per double-booked employee, carrying every clashing visit', () => {
		const warnings = scheduleWarnings({
			visitId: 'moving',
			proposal: proposal({ assignee_ids: ['sam', 'ana'] }),
			visits: [
				visit({ id: 'a', assignee_ids: ['sam'] }),
				visit({ id: 'b', assignee_ids: ['sam'], start_time: '10:30:00', end_time: '11:30:00' }),
				visit({ id: 'c', assignee_ids: ['ana'] })
			],
			workingWeek: null
		});
		expect(warnings).toEqual([
			{ kind: 'overlap', employee_id: 'sam', visit_ids: ['a', 'b'] },
			{ kind: 'overlap', employee_id: 'ana', visit_ids: ['c'] }
		]);
	});
});

describe('scheduleWarnings — working hours', () => {
	it('says nothing when the slot sits inside the confirmed hours', () => {
		expect(
			scheduleWarnings({
				visitId: 'moving',
				proposal: proposal(),
				visits: [],
				workingWeek: weekdayHours
			})
		).toEqual([]);
	});

	it('warns when the slot runs past closing', () => {
		expect(
			scheduleWarnings({
				visitId: 'moving',
				proposal: proposal({ start_time: '16:00', end_time: '18:00' }),
				visits: [],
				workingWeek: weekdayHours
			})
		).toEqual([{ kind: 'outside_hours' }]);
	});

	it('warns once for a day the business is closed, whatever the hour', () => {
		// 2026-09-05 is a Saturday.
		expect(
			scheduleWarnings({
				visitId: 'moving',
				proposal: proposal({ visit_date: '2026-09-05' }),
				visits: [],
				workingWeek: weekdayHours
			})
		).toEqual([{ kind: 'closed_day' }]);
	});

	it('warns about an Anytime visit on a closed day but not about its hours', () => {
		expect(
			scheduleWarnings({
				visitId: 'moving',
				proposal: proposal({ start_time: null, end_time: null, all_day: true }),
				visits: [],
				workingWeek: weekdayHours
			})
		).toEqual([]);
	});

	it('stays quiet when the business has no confirmed weekly pattern', () => {
		expect(
			scheduleWarnings({
				visitId: 'moving',
				proposal: proposal({ start_time: '03:00', end_time: '04:00' }),
				visits: [],
				workingWeek: null
			})
		).toEqual([]);
	});
});

describe('scheduleWarnings — unscheduled', () => {
	it('has nothing to say about a visit going back to the backlog', () => {
		expect(
			scheduleWarnings({
				visitId: 'moving',
				proposal: proposal({ visit_date: null, start_time: null, end_time: null }),
				visits: [visit({ id: 'other' })],
				workingWeek: weekdayHours
			})
		).toEqual([]);
	});
});

describe('scheduleWarnings — member availability', () => {
	// 2026-09-02 is a Wednesday, weekday 3. Sam works 08:00-16:30 that day and not at all on Saturday.
	const samsWeek = teamAvailability(
		[
			{ user_id: 'sam', weekday: 3, is_working: true, starts_at: '08:00:00', ends_at: '16:30:00' },
			{ user_id: 'sam', weekday: 6, is_working: false, starts_at: null, ends_at: null }
		],
		[]
	);

	it('says nothing when the slot sits inside the person’s own hours', () => {
		expect(
			scheduleWarnings({
				visitId: 'moving',
				proposal: proposal({ start_time: '10:00', end_time: '12:00' }),
				visits: [],
				workingWeek: null,
				teamAvailability: samsWeek
			})
		).toEqual([]);
	});

	it('warns when the slot runs past the end of their day', () => {
		expect(
			scheduleWarnings({
				visitId: 'moving',
				proposal: proposal({ start_time: '15:00', end_time: '18:00' }),
				visits: [],
				workingWeek: null,
				teamAvailability: samsWeek
			})
		).toEqual([{ kind: 'member_unavailable', employee_id: 'sam', reason: 'outside_their_hours' }]);
	});

	it('warns about a day they do not work at all', () => {
		expect(
			scheduleWarnings({
				visitId: 'moving',
				proposal: proposal({ visit_date: '2026-09-05' }),
				visits: [],
				workingWeek: null,
				teamAvailability: samsWeek
			})
		).toEqual([{ kind: 'member_unavailable', employee_id: 'sam', reason: 'off_that_day' }]);
	});

	it('warns about booked leave, which beats the ordinary week', () => {
		const onLeave = teamAvailability(
			[
				{ user_id: 'sam', weekday: 3, is_working: true, starts_at: '08:00:00', ends_at: '16:30:00' }
			],
			[
				{
					user_id: 'sam',
					exception_date: '2026-09-02',
					is_working: false,
					starts_at: null,
					ends_at: null
				}
			]
		);

		expect(
			scheduleWarnings({
				visitId: 'moving',
				proposal: proposal({ start_time: '10:00', end_time: '12:00' }),
				visits: [],
				workingWeek: null,
				teamAvailability: onLeave
			})
		).toEqual([{ kind: 'member_unavailable', employee_id: 'sam', reason: 'off_that_day' }]);
	});

	// The whole point of leaving availability unset: an unknown is never warned about.
	it('stays quiet about somebody whose availability nobody has set', () => {
		expect(
			scheduleWarnings({
				visitId: 'moving',
				proposal: proposal({ assignee_ids: ['nobody-set-this-one'] }),
				visits: [],
				workingWeek: null,
				teamAvailability: samsWeek
			})
		).toEqual([]);
	});

	it('stays quiet when the page has no availability loaded at all', () => {
		expect(
			scheduleWarnings({
				visitId: 'moving',
				proposal: proposal({ visit_date: '2026-09-05' }),
				visits: [],
				workingWeek: null
			})
		).toEqual([]);
	});

	// An Anytime visit claims no hour, so only the day can be judged.
	it('warns that an Anytime visit lands on their day off, but never about hours', () => {
		expect(
			scheduleWarnings({
				visitId: 'moving',
				proposal: proposal({ start_time: null, end_time: null, all_day: true }),
				visits: [],
				workingWeek: null,
				teamAvailability: samsWeek
			})
		).toEqual([]);

		expect(
			scheduleWarnings({
				visitId: 'moving',
				proposal: proposal({
					visit_date: '2026-09-05',
					start_time: null,
					end_time: null,
					all_day: true
				}),
				visits: [],
				workingWeek: null,
				teamAvailability: samsWeek
			})
		).toEqual([{ kind: 'member_unavailable', employee_id: 'sam', reason: 'off_that_day' }]);
	});

	it('names each unavailable person once, even on a crew', () => {
		const crew = teamAvailability(
			[
				{ user_id: 'sam', weekday: 6, is_working: false, starts_at: null, ends_at: null },
				{ user_id: 'ali', weekday: 6, is_working: false, starts_at: null, ends_at: null }
			],
			[]
		);

		expect(
			scheduleWarnings({
				visitId: 'moving',
				proposal: proposal({ visit_date: '2026-09-05', assignee_ids: ['sam', 'ali'] }),
				visits: [],
				workingWeek: null,
				teamAvailability: crew
			})
		).toEqual([
			{ kind: 'member_unavailable', employee_id: 'sam', reason: 'off_that_day' },
			{ kind: 'member_unavailable', employee_id: 'ali', reason: 'off_that_day' }
		]);
	});
});
