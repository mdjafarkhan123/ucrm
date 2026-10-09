import { describe, expect, it } from 'vitest';
import {
	bookingChangeSchema,
	bookingDecisionSchema,
	bookingHoursSchema,
	bookingSlotsQuerySchema,
	publicBookingSchema
} from './booking.schema';

const visitor = {
	starts_at: '2026-10-14T09:00:00Z',
	name: 'Sam Roofer',
	email: ' Sam@Example.com ',
	phone: '+44 7700 900123',
	business_name: 'Sam Roofing',
	country_code: 'gb',
	trade: 'Roofing',
	note: '',
	time_zone: 'Europe/London'
};

describe('weekly hours', () => {
	it('accepts split days', () => {
		const hours = [
			{ weekday: 1, start: '09:00', end: '12:00' },
			{ weekday: 1, start: '13:00', end: '17:00' }
		];
		expect(bookingHoursSchema.safeParse(hours).success).toBe(true);
	});

	it('refuses a range that ends before it starts', () => {
		const result = bookingHoursSchema.safeParse([{ weekday: 1, start: '17:00', end: '09:00' }]);
		expect(result.error?.issues[0]).toMatchObject({
			path: [0, 'end'],
			message: 'End after it starts.'
		});
	});

	it('refuses ranges that overlap on the same day, but not on different days', () => {
		const overlapping = [
			{ weekday: 2, start: '09:00', end: '12:00' },
			{ weekday: 2, start: '11:00', end: '14:00' }
		];
		expect(bookingHoursSchema.safeParse(overlapping).error?.issues[0].message).toBe(
			'This overlaps another range on the same day.'
		);
		const differentDays = overlapping.map((range, index) => ({ ...range, weekday: index + 2 }));
		expect(bookingHoursSchema.safeParse(differentDays).success).toBe(true);
	});
});

describe('open times request', () => {
	it('allows up to 45 days at a time', () => {
		const ok = { from: '2026-10-01T00:00:00Z', to: '2026-11-15T00:00:00Z' };
		const tooLong = { from: '2026-10-01T00:00:00Z', to: '2026-11-15T00:00:01Z' };
		expect(bookingSlotsQuerySchema.safeParse(ok).success).toBe(true);
		expect(bookingSlotsQuerySchema.safeParse(tooLong).success).toBe(false);
		expect(
			bookingSlotsQuerySchema.safeParse({ from: '2026-10-01', to: '2026-10-02' }).success
		).toBe(false);
	});
});

describe('a visitor booking', () => {
	it('tidies the details', () => {
		const result = publicBookingSchema.parse(visitor);
		expect(result.email).toBe('sam@example.com');
		expect(result.country_code).toBe('GB');
		expect(result.note).toBeNull();
		expect(result.turnstile_token).toBe('');
	});

	it('wants a full phone number with digits only', () => {
		const short = publicBookingSchema.safeParse({ ...visitor, phone: '+44 12' });
		expect(short.error?.issues[0].message).toBe('Enter the full number, with its country code.');
		const letters = publicBookingSchema.safeParse({ ...visitor, phone: 'call me maybe' });
		expect(letters.error?.issues[0].message).toBe('Use digits, spaces and + only.');
	});

	it('refuses fields the page never sends', () => {
		expect(publicBookingSchema.safeParse({ ...visitor, host_member_id: 'x' }).success).toBe(false);
	});
});

describe("a visitor's change", () => {
	it('moves to a time, or cancels with an optional reason', () => {
		expect(
			bookingChangeSchema.safeParse({ action: 'move', starts_at: '2026-10-14T09:00:00Z' }).success
		).toBe(true);
		expect(bookingChangeSchema.safeParse({ action: 'move' }).success).toBe(false);
		expect(bookingChangeSchema.parse({ action: 'cancel', reason: '  ' })).toEqual({
			action: 'cancel',
			reason: null
		});
		expect(
			bookingChangeSchema.safeParse({ action: 'cancel', reason: 'x'.repeat(501) }).success
		).toBe(false);
	});
});

describe("Jafar's answer to a request", () => {
	it('approves as asked or at another time, or declines', () => {
		expect(bookingDecisionSchema.safeParse({ decision: 'approve' }).success).toBe(true);
		expect(
			bookingDecisionSchema.safeParse({
				decision: 'approve',
				starts_at: '2026-10-14T09:00:00+06:00'
			}).success
		).toBe(true);
		expect(bookingDecisionSchema.safeParse({ decision: 'decline' }).success).toBe(true);
	});

	it('refuses a time on a decline and anything else', () => {
		expect(
			bookingDecisionSchema.safeParse({ decision: 'decline', starts_at: '2026-10-14T09:00:00Z' })
				.success
		).toBe(false);
		expect(bookingDecisionSchema.safeParse({ decision: 'maybe' }).success).toBe(false);
		expect(
			bookingDecisionSchema.safeParse({ decision: 'approve', starts_at: 'tomorrow' }).success
		).toBe(false);
	});
});
