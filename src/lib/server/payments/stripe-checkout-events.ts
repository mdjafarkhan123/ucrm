import type Stripe from 'stripe';
import { env } from '$env/dynamic/private';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { createPaymentReceiptEmailAccessLink } from '$lib/server/communications/receipt-email';
import { stripeClientForOrganization } from './stripe-connection';

// The one place that reacts to a Stripe Checkout confirmation, for either an invoice payment
// (docs/online-payments-behavior-contract.md §3) or a quote deposit (§4). The webhook route calls this without
// caring which one a checkout is for — `apply_stripe_checkout_event` decides that from the row itself. Nothing
// here trusts an amount from the webhook payload: the database re-applies the amounts it stored when the
// checkout was opened, not the ones Stripe echoes back.

export function appOrigin() {
	const raw = env.APP_URL?.trim();
	if (!raw) throw new Error('APP_URL must be set before customers can pay online.');
	return new URL(raw).origin;
}

const CHECKOUT_EVENTS = new Set([
	'checkout.session.completed',
	'checkout.session.async_payment_succeeded',
	'checkout.session.async_payment_failed'
]);

const BANK_METHODS = new Set([
	'us_bank_account',
	'sepa_debit',
	'bacs_debit',
	'acss_debit',
	'au_becs_debit',
	'nz_bank_account',
	'customer_balance'
]);

// Which ledger method the money arrived by. Cards, wallets (Apple Pay, Google Pay) and Link are all card
// payments; debits and transfers are bank payments; anything else (buy now, pay later) is "Online payment".
async function paymentMethodFor(stripe: Stripe, paymentIntentId: string | null) {
	if (!paymentIntentId) return 'stripe_other';
	try {
		const intent = await stripe.paymentIntents.retrieve(paymentIntentId, {
			expand: ['latest_charge']
		});
		const charge = intent.latest_charge as Stripe.Charge | null;
		const type = charge?.payment_method_details?.type;
		if (type === 'card' || type === 'card_present' || type === 'link') return 'stripe_card';
		if (type && BANK_METHODS.has(type)) return 'stripe_bank';
		return 'stripe_other';
	} catch {
		return 'stripe_other';
	}
}

/** Apply one verified Stripe event for the organization whose connection it arrived on. Throws only for our own
 *  failures (database down), so Stripe retries those; every business outcome is acknowledged. */
export async function handleStripeEvent(organizationId: string, event: Stripe.Event) {
	if (!CHECKOUT_EVENTS.has(event.type)) return { outcome: 'ignored' };

	const session = event.data.object as Stripe.Checkout.Session;
	const paymentIntentId =
		typeof session.payment_intent === 'string'
			? session.payment_intent
			: (session.payment_intent?.id ?? null);

	const confirmsMoney =
		(event.type === 'checkout.session.completed' && session.payment_status === 'paid') ||
		event.type === 'checkout.session.async_payment_succeeded';

	let method: string | null = null;
	if (confirmsMoney) {
		const connection = await stripeClientForOrganization(organizationId);
		method = connection
			? await paymentMethodFor(connection.stripe, paymentIntentId)
			: 'stripe_other';
	}

	const checkoutId = session.client_reference_id;
	const { data, error } = await getOwnerSupabaseClient().rpc('apply_stripe_checkout_event', {
		target_organization_id: organizationId,
		stripe_event_id: event.id,
		stripe_event_type: event.type,
		target_checkout_id: checkoutId && /^[0-9a-f-]{36}$/i.test(checkoutId) ? checkoutId : null,
		target_checkout_session_id: session.id,
		session_payment_status: session.payment_status,
		session_amount_total: session.amount_total,
		session_currency: session.currency,
		new_payment_intent_id: paymentIntentId,
		new_method: method
	});
	if (error) throw error;

	const result = data as {
		outcome: string;
		payment_event_id: string | null;
		send_receipt: boolean;
	};
	if (result.send_receipt && result.payment_event_id) {
		await sendAutomaticReceipt(organizationId, result.payment_event_id);
	}
	return result;
}

// Best effort. The payment is already recorded; a business with no verified email sender, or a customer with no
// email address, simply gets no automatic receipt, and staff can still send one from the payment. Invoice
// payments only — a quote deposit's `send_receipt` is always false, the same as an offline (cash/check) deposit.
async function sendAutomaticReceipt(organizationId: string, paymentEventId: string) {
	try {
		const link = createPaymentReceiptEmailAccessLink();
		const { error } = await getOwnerSupabaseClient().rpc('enqueue_payment_receipt_email', {
			target_organization_id: organizationId,
			target_actor_user_id: null,
			target_payment_event_id: paymentEventId,
			target_logical_send_key: `stripe-receipt:${paymentEventId}`,
			target_receipt_url: link.url,
			target_receipt_token_hash: link.tokenHash
		});
		if (error) console.warn('No automatic receipt was sent for an online payment.', error.code);
	} catch (error) {
		console.warn('No automatic receipt was sent for an online payment.', error);
	}
}
