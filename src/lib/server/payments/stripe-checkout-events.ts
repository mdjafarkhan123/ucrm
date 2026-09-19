import type Stripe from 'stripe';
import { env } from '$env/dynamic/private';
import type { Database } from '$lib/database.types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { createPaymentReceiptEmailAccessLink } from '$lib/server/communications/receipt-email';
import { stripeClientForOrganization } from './stripe-connection';

// The generated Args types mark every scalar param as required and non-null: Postgres exposes no "this param
// accepts null" metadata for a plain argument that has no default. Several params below are genuinely
// nullable (Stripe itself hands back null fields, and the SQL functions already branch on that), so the calls
// below cast to the generator's type rather than lying to it with `??` fallbacks that would change behavior.
type FunctionArgs<Fn extends keyof Database['public']['Functions']> =
	Database['public']['Functions'][Fn]['Args'];

// The one place that reacts to a Stripe event for a checkout, its refund, or a dispute — an invoice payment
// (docs/online-payments-behavior-contract.md §3), a quote deposit (§4), or either one's refund/dispute (§5).
// The webhook route calls this without caring which kind of checkout is underneath — the database functions
// decide that from the row itself. Nothing here trusts an amount from the webhook payload: the database
// re-applies the amounts it stored when the checkout was opened, or the amount Stripe's own signed refund/
// dispute object carries, never one echoed back through anything a customer's browser could have touched.

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

const REFUND_EVENTS = new Set(['refund.created', 'refund.updated', 'refund.failed']);
const DISPUTE_EVENTS = new Set(['charge.dispute.created']);

// Stripe's Refund.status values, collapsed to the three this product records. 'requires_action' and
// 'canceled' are rare edges (mandate or payment-method issues); treated as pending and failed respectively so
// nothing here has to invent a fourth ledger meaning for them.
function refundOutcomeFor(status: string | null): 'pending' | 'succeeded' | 'failed' {
	if (status === 'succeeded') return 'succeeded';
	if (status === 'failed' || status === 'canceled') return 'failed';
	return 'pending';
}

function idOf(value: string | { id: string } | null | undefined): string | null {
	if (!value) return null;
	return typeof value === 'string' ? value : value.id;
}

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

// Shared by the webhook route (refund.created / refund.updated / refund.failed) and, directly, by the refund route
// right after Stripe's synchronous response to its own refunds.create() call (docs/online-payments-behavior-
// contract.md §5). One code path either way: `apply_stripe_refund_event` is keyed by Stripe's own refund id,
// so telling it about the same refund twice — once synchronously, once by webhook — moves it out of 'pending'
// exactly once, whichever telling arrives first.
export async function applyStripeRefund(
	organizationId: string,
	sourceEventId: string,
	sourceEventType: string,
	refund: Stripe.Refund
) {
	const { data, error } = await getOwnerSupabaseClient().rpc('apply_stripe_refund_event', {
		target_organization_id: organizationId,
		stripe_event_id: `${sourceEventId}:${refund.id}`,
		stripe_event_type: sourceEventType,
		target_stripe_refund_id: refund.id,
		target_payment_intent_id: idOf(refund.payment_intent),
		refund_status: refundOutcomeFor(refund.status),
		refund_amount_minor: refund.amount,
		refund_currency: refund.currency.toUpperCase(),
		refund_failure_message: refund.failure_reason ?? null
	} as FunctionArgs<'apply_stripe_refund_event'>);
	if (error) throw error;
	return data as { outcome: string; refund_id: string | null };
}

/** Apply one verified Stripe event for the organization whose connection it arrived on. Throws only for our own
 *  failures (database down), so Stripe retries those; every business outcome is acknowledged. */
export async function handleStripeEvent(organizationId: string, event: Stripe.Event) {
	if (REFUND_EVENTS.has(event.type)) {
		// Every refund.* event's data.object is the Refund itself. apply_stripe_refund_event is idempotent
		// per Stripe refund id, so redelivery or telling it the same refund at two different statuses is safe.
		const refund = event.data.object as Stripe.Refund;
		return applyStripeRefund(organizationId, event.id, event.type, refund);
	}

	if (DISPUTE_EVENTS.has(event.type)) {
		const dispute = event.data.object as Stripe.Dispute;
		const { data, error } = await getOwnerSupabaseClient().rpc('apply_stripe_dispute_event', {
			target_organization_id: organizationId,
			stripe_event_id: event.id,
			stripe_event_type: event.type,
			target_payment_intent_id: idOf(dispute.payment_intent),
			dispute_amount_minor: dispute.amount,
			dispute_currency: dispute.currency.toUpperCase(),
			dispute_reason: dispute.reason ?? null
		} as FunctionArgs<'apply_stripe_dispute_event'>);
		if (error) throw error;
		return data as { outcome: string };
	}

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
	} as FunctionArgs<'apply_stripe_checkout_event'>);
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
		} as unknown as FunctionArgs<'enqueue_payment_receipt_email'>);
		if (error) console.warn('No automatic receipt was sent for an online payment.', error.code);
	} catch (error) {
		console.warn('No automatic receipt was sent for an online payment.', error);
	}
}
