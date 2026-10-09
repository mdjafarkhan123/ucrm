// Client reminders Part 4: whether saving a booking can email the customer. A scheduling screen shows its
// "Notify customer" box only while the matching automation is on (docs/client-reminders-behavior-contract.md
// § "You're booked" confirmation), and sends the box's value with the save.

export type CustomerNoticeStatus = {
	/** "Booking confirmation" is on: a first booking can send "You're booked". */
	booked: boolean;
	/** "Visit moved" is on: moving a booked visit can send the new time. */
	rescheduled: boolean;
};

export type CustomerNoticeKind = keyof CustomerNoticeStatus;

export const customerNoticeStatusKey = ['schedule', 'customer-notices'] as const;

export async function fetchCustomerNoticeStatus(): Promise<CustomerNoticeStatus> {
	const response = await fetch('/api/schedule/customer-notices');
	if (!response.ok) return { booked: false, rescheduled: false };
	return response.json();
}

/** What the save answered: which email it queued for the customer, if any. */
export type CustomerNoticeSent = 'booked' | 'rescheduled' | null;

export function customerNoticeToast(notice: CustomerNoticeSent | undefined): string | null {
	if (notice === 'booked') return 'The customer will get a booking confirmation.';
	if (notice === 'rescheduled') return 'The customer will get the new time by email.';
	return null;
}
