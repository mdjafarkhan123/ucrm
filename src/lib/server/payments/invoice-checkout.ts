import type Stripe from 'stripe';
import { env } from '$env/dynamic/private';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { createPaymentReceiptEmailAccessLink } from '$lib/server/communications/receipt-email';
import type { CustomerInvoicePayment } from '$lib/invoices/customer-document';
import { stripeClientForOrganization } from './stripe-connection';

// A customer paying an issued invoice online (docs/online-payments-behavior-contract.md §3). The database decides
// whether the link may take money and how much; this module only talks to Stripe. Nothing here trusts an amount
// from the browser or from a webhook payload: open_invoice_stripe_checkout re-checks the amount under a lock,
// and apply_stripe_checkout_event records the amounts it stored, not the ones Stripe echoes back.

export type InvoicePaymentUnavailableReason =
	'business_unavailable' | 'not_connected' | 'turned_off' | 'closed' | 'nothing_owed';

export type InvoicePaymentContext = {
	organization_id: string;
	invoice_id: string;
	client_id: string;
	invoice_number: number;
	currency_code: string;
	available: boolean;
	unavailable_reason: InvoicePaymentUnavailableReason | null;
	balance_minor: number;
	processing_minor: number;
	recent_paid_minor: number;
	partial_allowed: boolean;
	tips_enabled: boolean;
	tip_base_minor: number;
	livemode: boolean | null;
	stripe_account_id: string | null;
};

/** The part of the context the customer's browser may see: amounts and switches, no ids. */
export function customerPaymentView(
	context: InvoicePaymentContext | null
): CustomerInvoicePayment | null {
	if (!context || context.unavailable_reason === 'not_connected') return null;
	return {
		available: context.available,
		balance_minor: context.balance_minor,
		processing_minor: context.processing_minor,
		recent_paid_minor: context.recent_paid_minor,
		partial_allowed: context.partial_allowed,
		tips_enabled: context.tips_enabled,
		tip_base_minor: context.tip_base_minor,
		test_mode: context.livemode === false
	};
}

export async function getInvoicePaymentContext(
	tokenHash: string
): Promise<InvoicePaymentContext | null> {
	const { data, error } = await getOwnerSupabaseClient().rpc('invoice_online_payment_context', {
		supplied_token_hash: tokenHash
	});
	if (error) throw error;
	return (data as InvoicePaymentContext | null) ?? null;
}

export type OpenCheckoutResult =
	| { ok: true; url: string }
	| {
			ok: false;
			reason: 'unavailable' | 'amount' | 'tip' | 'stripe_rejected' | 'stripe_unavailable';
	  };

function appOrigin() {
	const raw = env.APP_URL?.trim();
	if (!raw) throw new Error('APP_URL must be set before customers can pay online.');
	return new URL(raw).origin;
}

export async function openInvoiceCheckout(input: {
	token: string;
	tokenHash: string;
	amountMinor: number;
	tipMinor: number;
}): Promise<OpenCheckoutResult> {
	const db = getOwnerSupabaseClient();
	const { data, error } = await db.rpc('open_invoice_stripe_checkout', {
		supplied_token_hash: input.tokenHash,
		new_amount_minor: input.amountMinor,
		new_tip_minor: input.tipMinor
	});
	if (error) {
		if (error.code === '23514' && (error.details === 'amount' || error.details === 'tip')) {
			return { ok: false, reason: error.details };
		}
		if (error.code === '23514' || error.code === 'P0404')
			return { ok: false, reason: 'unavailable' };
		throw error;
	}

	const opened = data as InvoicePaymentContext & { checkout_id: string };
	const connection = await stripeClientForOrganization(opened.organization_id);
	// Disconnected between the check and now, or reconnected to another Stripe account.
	if (!connection || connection.stripeAccountId !== opened.stripe_account_id) {
		await markFailed(opened.checkout_id);
		return { ok: false, reason: 'unavailable' };
	}

	const currency = opened.currency_code.toLowerCase();
	const lineItems: Stripe.Checkout.SessionCreateParams.LineItem[] = [
		{
			quantity: 1,
			price_data: {
				currency,
				unit_amount: input.amountMinor,
				product_data: { name: `Invoice #${opened.invoice_number}` }
			}
		}
	];
	if (input.tipMinor > 0) {
		lineItems.push({
			quantity: 1,
			price_data: { currency, unit_amount: input.tipMinor, product_data: { name: 'Tip' } }
		});
	}

	const metadata = {
		ucrm_checkout_id: opened.checkout_id,
		ucrm_invoice_id: opened.invoice_id,
		ucrm_organization_id: opened.organization_id
	};
	const returnUrl = `${appOrigin()}/i/${encodeURIComponent(input.token)}`;

	let session: Stripe.Checkout.Session;
	try {
		// No payment_method_types: Stripe offers whatever the contractor switched on in their dashboard for this
		// customer's country and currency (cards, wallets, bank payments).
		session = await connection.stripe.checkout.sessions.create(
			{
				mode: 'payment',
				client_reference_id: opened.checkout_id,
				line_items: lineItems,
				metadata,
				payment_intent_data: {
					description: `Invoice #${opened.invoice_number}`,
					metadata
				},
				success_url: `${returnUrl}?payment=success`,
				cancel_url: returnUrl
			},
			{ idempotencyKey: `ucrm-checkout-${opened.checkout_id}` }
		);
	} catch (stripeError) {
		await markFailed(opened.checkout_id);
		const type = (stripeError as { type?: string } | null)?.type;
		return {
			ok: false,
			reason: type === 'StripeInvalidRequestError' ? 'stripe_rejected' : 'stripe_unavailable'
		};
	}

	const { error: storeError } = await db
		.from('payment_stripe_checkouts')
		.update({ checkout_session_id: session.id, updated_at: new Date().toISOString() })
		.eq('id', opened.checkout_id)
		.is('checkout_session_id', null);
	// Not fatal: the webhook finds the row through client_reference_id and fills the session id in itself.
	if (storeError) console.error('Could not store the Stripe checkout session id.', storeError.code);

	if (!session.url) return { ok: false, reason: 'stripe_unavailable' };
	return { ok: true, url: session.url };
}

async function markFailed(checkoutId: string) {
	await getOwnerSupabaseClient()
		.from('payment_stripe_checkouts')
		.update({ status: 'failed', updated_at: new Date().toISOString() })
		.eq('id', checkoutId)
		.eq('status', 'open');
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
// email address, simply gets no automatic receipt, and staff can still send one from the payment.
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
