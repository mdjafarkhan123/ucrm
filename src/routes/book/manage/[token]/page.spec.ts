import { describe, expect, it } from 'vitest';
import { render } from 'svelte/server';
import Page from './+page.svelte';
import { managedBooking } from '$lib/server/jafar/booking-manage';
import type { BookingView } from '$lib/jafar/booking';

// The visitor's change-or-cancel link opens on the server first. Every state that shows the call's time must
// render with the booking's own zone, before the browser has said anything about it.

const DAY = 24 * 60 * 60 * 1000;

function view(overrides: Partial<BookingView> = {}): BookingView {
	const starts = new Date(Date.now() + 3 * DAY);
	return {
		booking_id: '7f0c7a8e-2f4b-4c1d-9a51-3b8d2c6e1f00',
		starts_at: starts.toISOString(),
		ends_at: new Date(starts.getTime() + 30 * 60 * 1000).toISOString(),
		name: 'Discovery call',
		duration_minutes: 30,
		location_kind: 'google_meet',
		video_join_url: null,
		host_name: 'Jafar Khan',
		status: 'booked',
		call_status: 'scheduled',
		entry_id: null,
		relationship_id: 'r1',
		slug: 'discovery-call',
		horizon_days: 60,
		visitor_name: 'Mike Turner',
		visitor_email: 'mike@example.test',
		visitor_phone: '+44 7700 900123',
		visitor_time_zone: 'Asia/Dhaka',
		business_name: 'Turner Roofing',
		video_link_source: null,
		video_link_mode: 'automatic',
		meeting_type_id: null,
		host_member_id: null,
		change_until: new Date(starts.getTime() - DAY).toISOString(),
		can_change: true,
		...overrides
	};
}

function renderPage(booking: BookingView) {
	return render(Page, {
		props: {
			data: { booking: managedBooking(booking), firstWindow: { to: '', starts: [] } },
			params: { token: 'x' }
		} as never
	}).body;
}

describe('the change-or-cancel page on first render', () => {
	it('shows an upcoming booking in the visitor’s zone', () => {
		const body = renderPage(view());
		expect(body).toContain('Your booking');
		expect(body).toContain('Dhaka time');
	});

	it('shows a cancelled call, struck through, in the visitor’s zone', () => {
		const body = renderPage(view({ call_status: 'cancelled', can_change: false }));
		expect(body).toContain('This call is cancelled');
		expect(body).toContain('Dhaka time');
	});

	it('shows a call too close to change in the visitor’s zone', () => {
		const body = renderPage(view({ can_change: false }));
		expect(body).toContain('too late to change online');
		expect(body).toContain('Dhaka time');
	});
});
