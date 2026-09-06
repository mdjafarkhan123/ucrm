import { error as httpError } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { requireContractor } from '$lib/server/auth/guards';
import type { CustomerPaymentReceipt } from '$lib/invoices/customer-receipt';

// The customer's receipt, for the staff member who wants to print it. It reads the same database function
// that builds the customer's receipt, so what is printed here is what was emailed — not a second rendering
// that agrees today and drifts tomorrow.
//
// It creates nothing. No link, no token: printing your own receipt is not sending it. This page breaks out of
// the app shell, so it does its own sign-in check rather than inheriting one.
export const load: PageServerLoad = async (event) => {
	await requireContractor(event);

	const { data, error } = await event.locals.supabase.rpc('payment_receipt_preview', {
		target_payment_event_id: event.params.id
	});

	if (error) throw httpError(403, 'You do not have access to this payment.');
	if (!data) throw httpError(404, 'This payment has no receipt to show.');

	return { document: data as unknown as CustomerPaymentReceipt };
};
