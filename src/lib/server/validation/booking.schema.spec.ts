import { describe, expect, it } from 'vitest';
import {
	bookingChangeSchema,
	bookingDecisionSchema,
	bookingHostChangeSchema,
	bookingHoursSchema,
	bookingSlotsQuerySchema,
	meetingTypeSchema,
	publicBookingSchema,
	videoLinkSchema
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

describe('meeting type (E3)', () => {
	const sam = '7d1c3c4e-5d0b-4a8e-9a39-0b1f2c3d4e5f';
	const type = {
		slug: 'pricing-call',
		name: 'Pricing call',
		description: '',
		duration_minutes: 30,
		location_kind: 'phone',
		video_link_mode: 'automatic',
		min_notice_minutes: 240,
		horizon_days: 60,
		buffer_minutes: 0,
		slot_interval_minutes: 30,
		requires_approval: false,
		change_deadline_minutes: 240,
		is_active: true,
		visitor_reminder_minutes: [1440],
		host_member_id: sam,
		host_member_ids: [null, sam, sam]
	};

	it('accepts a teammate as default host when they are one of the hosts, once each', () => {
		const result = meetingTypeSchema.safeParse(type);
		expect(result.data?.host_member_ids).toEqual([null, sam]);
		expect(result.data?.description).toBeNull();
	});

	it('refuses a default host who is not one of the hosts', () => {
		const result = meetingTypeSchema.safeParse({ ...type, host_member_ids: [null] });
		expect(result.error?.issues[0]).toMatchObject({
			path: ['host_member_id'],
			message: 'The default host must be one of the hosts.'
		});
	});

	it('needs at least one host', () => {
		const result = meetingTypeSchema.safeParse({
			...type,
			host_member_id: null,
			host_member_ids: []
		});
		expect(result.error?.issues[0].message).toBe('Choose at least one host.');
	});

	it('takes Jafar (null) or a teammate id as the new host of a call', () => {
		expect(bookingHostChangeSchema.safeParse({ member_id: null }).success).toBe(true);
		expect(bookingHostChangeSchema.safeParse({ member_id: sam }).success).toBe(true);
		expect(bookingHostChangeSchema.safeParse({ member_id: 'sam' }).success).toBe(false);
	});
});

describe('video (E4a)', () => {
	it('takes a full https joining link, trimmed', () => {
		expect(videoLinkSchema.parse({ url: ' https://zoom.us/j/123?pwd=x ' }).url).toBe(
			'https://zoom.us/j/123?pwd=x'
		);
	});

	it('refuses anything that is not a full https link', () => {
		for (const url of [
			'',
			'zoom.us/j/123',
			'http://zoom.us/j/1',
			'https://localhost/x',
			'javascript:alert(1)'
		])
			expect(videoLinkSchema.safeParse({ url }).success).toBe(false);
	});
});
