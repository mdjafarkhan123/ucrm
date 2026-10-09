import type { BookingView, ManagedBooking } from '$lib/jafar/booking';

// Jafar business management E2: what the visitor's link page may show. Their email address and the ids behind the
// booking stay on the server: a forwarded link shows the booking, not the address book.

export function managedBooking(view: BookingView): ManagedBooking {
	const {
		visitor_email: _email,
		relationship_id: _relationship,
		entry_id: _entry,
		...shown
	} = view;
	return shown;
}
