import { describe, expect, it } from 'vitest';
import { bookingConfirmationEmail } from './booking-confirmation';

const confirmation = {
	bookingId: '00000000-0000-0000-0000-000000000001',
	call: {
		starts_at: '2026-10-14T09:00:00+00:00',
		ends_at: '2026-10-14T09:30:00+00:00',
		name: 'Discovery call',
		duration_minutes: 30,
		location_kind: 'phone' as const,
		host_name: 'Jafar'
	},
	visitorName: 'Sam Roofer',
	visitorEmail: 'sam@example.com',
	visitorPhone: '+44 7700 900123',
	timeZone: 'Europe/London'
};

describe('booking confirmation email', () => {
	it('tells the visitor when, in their own zone, and how the call happens', () => {
		const email = bookingConfirmationEmail(confirmation);
		expect(email.subject).toBe(
			'Booked: Discovery call with Uplift, Wednesday, 14 October 2026 at 10:00'
		);
		expect(email.text).toContain('Hi Sam,');
		expect(email.text).toContain('Discovery call (30 min) with Jafar is booked.');
		expect(email.text).toContain('Wednesday, 14 October 2026, 10:00 – 10:30 (London time)');
		expect(email.text).toContain('Jafar will phone you on +44 7700 900123.');
	});

	it('never lets a visitor write HTML into the email', () => {
		const email = bookingConfirmationEmail({ ...confirmation, visitorName: '<b>Sam</b> Roofer' });
		expect(email.html).toContain('Hi &lt;b&gt;Sam&lt;/b&gt;,');
		expect(email.html).not.toContain('<b>Sam');
	});
});
