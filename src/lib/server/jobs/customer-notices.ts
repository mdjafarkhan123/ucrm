import type { SupabaseClient } from '@supabase/supabase-js';
import type { CustomerNoticeSent } from '$lib/schedule/customer-notices';

// Client reminders Part 4: after a scheduling save, hand the screen's "Notify customer" box to
// `settle_appointment_notices`. The database already logged what the save changed; it decides whether that was a
// first booking or a move and queues at most one email. Called with the box unticked too, so the change log is
// cleared rather than picked up by a later save. The booking is already saved, so a failure here is logged and
// the save still succeeds.
export async function settleCustomerNotice(
	supabase: SupabaseClient,
	organizationId: string,
	booking: { type: 'job' | 'assessment'; id: string },
	notifyCustomer: boolean
): Promise<CustomerNoticeSent> {
	const { data, error } = await supabase.rpc('settle_appointment_notices', {
		target_organization_id: organizationId,
		target_booking_type: booking.type,
		target_booking_id: booking.id,
		notify_customer: notifyCustomer
	});
	if (error) {
		console.error('Could not settle the customer notice for a booking.', error);
		return null;
	}
	const notice = (data as { notice?: string | null } | null)?.notice;
	return notice === 'booked' || notice === 'rescheduled' ? notice : null;
}
