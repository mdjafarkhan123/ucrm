import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { enforceOrganizationWriteRateLimit } from '$lib/server/security/rate-limit';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { stripePaymentRefundSchema } from '$lib/server/validation/invoices.schema';
import { updateInvoiceError } from '$lib/server/invoices/errors';
import { sendReservedStripeRefund } from '$lib/server/payments/stripe-refunds';

// Online payments Part 5: sending money back through Stripe on this recorded payment. `id` is the payment_event
// id, same as the manual refund route it sits beside -- the two share can_correct_payment (refunding is
// refunding, whichever rail sends the money) but this one only ever moves a payment Stripe collected.
// reserve_stripe_payment_refund re-checks everything (the payment is a Stripe one, the amount is still there
// to refund), the same way refund_client_payment does for a manual refund, so this route repeats none of that
// arithmetic; it only sends the reservation to Stripe once the database has approved it.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.correct_payment');
	if ('response' in check) return check.response;

	const limited = await enforceOrganizationWriteRateLimit(
		event.locals.supabase,
		check.auth.organization.id,
		'payments'
	);
	if (limited) return limited;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = stripePaymentRefundSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	const input = parsed.data;

	const { data, error } = await event.locals.supabase.rpc('reserve_stripe_payment_refund', {
		target_organization_id: check.auth.organization.id,
		target_payment_event_id: event.params.id,
		new_amount_minor: input.amount_minor,
		new_idempotency_key: input.idempotency_key,
		new_request_hash: input.request_hash
	});
	if (error) return updateInvoiceError(error);

	const reserved = data as {
		refund_id: string;
		checkout_id: string;
		payment_intent_id: string | null;
		stripe_account_id: string;
		amount_minor: number;
		currency_code: string;
	};

	const sent = await sendReservedStripeRefund(check.auth.organization.id, reserved);
	if (!sent.ok) return validationError({ form: sent.message });

	return json({ status: sent.status }, { headers: NO_STORE_HEADERS });
};
