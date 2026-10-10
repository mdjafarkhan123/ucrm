import { describe, expect, it, vi } from 'vitest';
import type { BookingView } from '$lib/jafar/booking';

vi.mock('$lib/server/env', () => ({ getServerEnv: () => ({ SESSION_SECRET: 'test-secret' }) }));

const { bookingIcs, googleCalendarUrl } = await import('./booking-calendar');
const { bookingEmail } = await import('./booking-emails');

const booking: BookingView = {
	booking_id: '6c1f8f5e-7f62-4c55-9b0e-3b1f5d9a2c11',
	status: 'booked',
	call_status: 'scheduled',
	entry_id: 'b4a0c3f6-0a0e-4c1e-9d55-2f9b8d1e0a22',
	relationship_id: 'r',
	meeting_type_id: 't',
	starts_at: '2026-10-14T09:00:00.000Z',
	ends_at: '2026-10-14T09:30:00.000Z',
	name: 'Discovery call',
	slug: 'discovery-call',
	duration_minutes: 30,
	location_kind: 'phone',
	video_join_url: null,
	video_link_source: null,
	video_link_mode: 'automatic',
	horizon_days: 60,
	host_member_id: null,
	host_name: 'Jafar',
	visitor_name: 'Rahim Uddin',
	visitor_email: 'rahim@example.com',
	visitor_phone: '+880 1711 000000',
	visitor_time_zone: 'Asia/Dhaka',
	business_name: 'Rahim Plumbing, Ltd',
	change_until: '2026-10-14T05:00:00.000Z',
	can_change: true
};
const manage = 'https://app.example/book/manage/token';

describe('bookingIcs', () => {
	it('is one confirmed event at the booked time in UTC, with CRLF lines of at most 75 octets', () => {
		const ics = bookingIcs(booking, manage, new Date('2026-10-10T00:00:00Z'));
		expect(ics).toContain('DTSTART:20261014T090000Z\r\n');
		expect(ics).toContain('DTEND:20261014T093000Z\r\n');
		expect(ics).toContain(`UID:booking-${booking.booking_id}@uplift\r\n`);
		expect(ics).toContain('STATUS:CONFIRMED');
		expect(ics.endsWith('END:VCALENDAR\r\n')).toBe(true);
		for (const line of ics.split('\r\n'))
			expect(new TextEncoder().encode(line).length).toBeLessThanOrEqual(75);
	});

	it('escapes commas and semicolons, and marks a cancelled call cancelled', () => {
		const ics = bookingIcs(
			{ ...booking, name: 'Call; quick, please', call_status: 'cancelled' },
			manage
		);
		expect(ics).toContain('SUMMARY:Call\\; quick\\, please with Uplift');
		expect(ics).toContain('STATUS:CANCELLED');
	});

	it('a later file has a higher sequence, so calendars take the newer time', () => {
		const sequence = (ics: string) => Number(/SEQUENCE:(\d+)/.exec(ics)?.[1]);
		expect(sequence(bookingIcs(booking, manage, new Date('2026-10-11T00:00:00Z')))).toBeGreaterThan(
			sequence(bookingIcs(booking, manage, new Date('2026-10-10T00:00:00Z')))
		);
	});
});

describe('googleCalendarUrl', () => {
	it('fills in the call and its time', () => {
		const url = new URL(googleCalendarUrl(booking, manage));
		expect(url.searchParams.get('dates')).toBe('20261014T090000Z/20261014T093000Z');
		expect(url.searchParams.get('text')).toBe('Discovery call with Uplift');
	});
});

describe('reminder email', () => {
	it('names the call in the visitor zone and carries calendar and change links', () => {
		const email = bookingEmail(
			booking,
			{ kind: 'reminder', reminderId: 'x' },
			'https://app.example'
		);
		expect(email.subject).toBe(
			'Reminder: Discovery call with Uplift, Wednesday, 14 October 2026 at 15:00'
		);
		expect(email.text).toContain('A reminder of your Discovery call (30 min) with Jafar.');
		expect(email.text).toContain('Google Calendar: https://calendar.google.com/');
		expect(email.text).toMatch(/\.ics\): https:\/\/app\.example\/book\/manage\/.+\/calendar\.ics/);
		expect(email.text).toContain('Change or cancel: https://app.example/book/manage/');
	});
});

describe('video call (E4a)', () => {
	const zoom: BookingView = { ...booking, location_kind: 'zoom' };
	const join = 'https://us02web.zoom.us/j/81234567890?pwd=abc';

	it('promises the link will follow while there is none, and never shows a phone number', () => {
		const email = bookingEmail(zoom, { kind: 'booked' }, 'https://app.example');
		expect(email.text).toContain(
			'How: Zoom video call with Jafar. We will email you the joining link before the call.'
		);
		expect(email.text).not.toContain('+880');
		expect(bookingIcs(zoom, manage)).toContain('LOCATION:Zoom (link to follow by email)');
	});

	it('carries the joining link once there is one, in the email and the calendar files', () => {
		const linked = { ...zoom, video_join_url: join, video_link_source: 'custom' as const };
		const email = bookingEmail(
			linked,
			{ kind: 'reminder', reminderId: 'x' },
			'https://app.example'
		);
		expect(email.text).toContain(`Join the Zoom call: ${join}`);
		expect(email.html).toContain(`href="${join.replace('&', '&amp;')}"`);
		expect(new URL(googleCalendarUrl(linked, manage)).searchParams.get('location')).toBe(join);
	});

	it('sends a new or replaced link as its own email, once per link', () => {
		const linked = { ...zoom, video_join_url: join, video_link_source: 'custom' as const };
		const first = bookingEmail(
			linked,
			{ kind: 'video_link', replaced: false },
			'https://app.example'
		);
		const again = bookingEmail(
			linked,
			{ kind: 'video_link', replaced: true },
			'https://app.example'
		);
		expect(first.subject).toBe(
			'Joining link: Discovery call with Uplift, Wednesday, 14 October 2026 at 15:00'
		);
		expect(again.subject.startsWith('New joining link:')).toBe(true);
		expect(again.text).toContain('the old link will not work');
	});
});
