import { describe, expect, it } from 'vitest';
import { appointmentReminderTimingText } from './catalog';

describe('appointmentReminderTimingText', () => {
	it('says how long before the visit', () => {
		expect(appointmentReminderTimingText({ mode: 'before', amount: 1, unit: 'days' })).toBe(
			'1 day before'
		);
		expect(appointmentReminderTimingText({ mode: 'before', amount: 3, unit: 'hours' })).toBe(
			'3 hours before'
		);
	});

	it('says the day and clock time for a fixed time of day', () => {
		expect(
			appointmentReminderTimingText({ mode: 'fixed_time', days_before: 1, time: '18:00' })
		).toBe('the day before at 6:00 PM');
		expect(
			appointmentReminderTimingText({ mode: 'fixed_time', days_before: 2, time: '00:30' })
		).toBe('2 days before at 12:30 AM');
	});

	it('falls back to the default when the timing is missing', () => {
		expect(appointmentReminderTimingText(undefined)).toBe('1 day before');
	});
});
