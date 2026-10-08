import { describe, expect, it } from 'vitest';
import {
	durationWords,
	orderCalendarDay,
	placeCalendarItems,
	reminderLabel,
	zonedInstant,
	zonedPlace,
	type CalendarEntry,
	type CalendarFollowUp
} from './calendar';

const entry = (overrides: Partial<CalendarEntry>): CalendarEntry => ({
	id: 'e1',
	kind: 'call',
	relationship_id: 'r1',
	business_name: 'Bright Roofing',
	title: null,
	starts_at: '2026-10-08T09:00:00Z',
	ends_at: '2026-10-08T09:30:00Z',
	status: 'scheduled',
	owner_member_id: null,
	deal_stage: null,
	...overrides
});

const followUp = (overrides: Partial<CalendarFollowUp>): CalendarFollowUp => ({
	id: 'r2',
	business_name: 'Clear Gutters',
	next_action: 'Send pricing',
	due_on: '2026-10-08',
	due_at: null,
	first_contact: false,
	deal_stage: null,
	...overrides
});

describe('time zones', () => {
	it('round-trips a day and minutes through an instant', () => {
		const instant = zonedInstant('2026-10-08', 15 * 60, 'Asia/Dhaka');
		expect(instant).toBe('2026-10-08T09:00:00.000Z');
		expect(zonedPlace(instant, 'Asia/Dhaka')).toEqual({ day: '2026-10-08', minutes: 900 });
	});
});

describe('placeCalendarItems', () => {
	it('puts a call at its local time and a day-only follow-up in the top lane', () => {
		const days = placeCalendarItems(
			{ entries: [entry({})], follow_ups: [followUp({})], truncated: false },
			'Asia/Dhaka'
		);
		const day = days.get('2026-10-08')!;
		expect(day.timed).toHaveLength(1);
		expect(day.timed[0]).toMatchObject({ start: 900, end: 930 });
		expect(day.anytime.map((item) => item.id)).toEqual(['follow-up:r2']);
	});

	it('cuts something running past midnight across both days', () => {
		const days = placeCalendarItems(
			{
				entries: [
					entry({ kind: 'busy', starts_at: '2026-10-08T17:00:00Z', ends_at: '2026-10-08T19:00:00Z' })
				],
				follow_ups: [],
				truncated: false
			},
			'Asia/Dhaka'
		);
		expect(days.get('2026-10-08')!.timed[0]).toMatchObject({ start: 23 * 60, end: 24 * 60 });
		expect(days.get('2026-10-09')!.timed[0]).toMatchObject({ start: 0, end: 60 });
	});

	it('leaves out cancelled calls and orders a day for reading', () => {
		const days = placeCalendarItems(
			{
				entries: [
					entry({ id: 'late', starts_at: '2026-10-08T10:00:00Z', ends_at: '2026-10-08T10:30:00Z' }),
					entry({ id: 'early' }),
					entry({ id: 'gone', status: 'cancelled' })
				],
				follow_ups: [followUp({})],
				truncated: false
			},
			'UTC'
		);
		expect(orderCalendarDay(days.get('2026-10-08')).map((item) => item.id)).toEqual([
			'follow-up:r2',
			'entry:early',
			'entry:late'
		]);
	});
});

describe('reminder words', () => {
	it('names reminders the way Google Calendar does', () => {
		expect(durationWords(1440)).toBe('1 day');
		expect(reminderLabel({ channel: 'email', minutes_before: 1440 })).toBe('Email 1 day before');
		expect(reminderLabel({ channel: 'in_app', minutes_before: 0 })).toBe('Alert at the time');
		expect(reminderLabel({ channel: 'in_app', days_before: 0, at: '09:00' })).toBe(
			'Alert on the day at 9am'
		);
	});
});
