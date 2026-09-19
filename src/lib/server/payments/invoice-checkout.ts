import type Stripe from 'stripe';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import type { CustomerInvoicePayment } from '$lib/invoices/customer-document';
import { hasAnyPayByAppMethod, type PayByAppMethods } from '$lib/payments/pay-by-app';
import { stripeClientForOrganization } from './stripe-connection';
import { appOrigin } from './stripe-checkout-events';

// A customer paying an issued invoice online (docs/online-payments-behavior-contract.md §3). The database decides
// whether the link may take money and how much; this module only talks to Stripe. Nothing here trusts an amount
// from the browser or from a webhook payload: open_invoice_stripe_checkout re-checks the amount under a lock,
// and apply_stripe_checkout_event (in ./stripe-checkout-events, shared with quote deposits) records the amounts
// it stored, not the ones Stripe echoes back.

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
	pay_by_app: PayByAppMethods;
};

/** The part of the context the customer's browser may see: amounts and switches, no ids. */
export function customerPaymentView(
	context: InvoicePaymentContext | null
): CustomerInvoicePayment | null {
	if (!context) return null;
	const payByApp = hasAnyPayByAppMethod(context.pay_by_app) ? context.pay_by_app : null;
	// Pay-by-app has nothing to do with Stripe, so a business with no Stripe connection still gets to show
	// it. Only when there is truly nothing -- no Stripe and no pay-by-app method either -- is there no page
	// to draw at all.
	if (context.unavailable_reason === 'not_connected' && !payByApp) return null;
	return {
		available: context.available,
		balance_minor: context.balance_minor,
		processing_minor: context.processing_minor,
		recent_paid_minor: context.recent_paid_minor,
		partial_allowed: context.partial_allowed,
		tips_enabled: context.tips_enabled,
		tip_base_minor: context.tip_base_minor,
		test_mode: context.livemode === false,
		pay_by_app: payByApp
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
