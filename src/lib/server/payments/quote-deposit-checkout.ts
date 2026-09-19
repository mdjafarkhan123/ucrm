import type Stripe from 'stripe';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import type { CustomerQuoteDepositPayment } from '$lib/quotes/customer-document';
import { hasAnyPayByAppMethod, type PayByAppMethods } from '$lib/payments/pay-by-app';
import { stripeClientForOrganization } from './stripe-connection';
import { appOrigin } from './stripe-checkout-events';

// A customer paying a quote's deposit online (docs/online-payments-behavior-contract.md §4). Mirrors
// invoice-checkout.ts, minus the amount and tip choices an invoice offers: a deposit is one fixed figure the
// customer already agreed to when they signed. The database decides whether the link may take money;
// open_quote_deposit_stripe_checkout re-checks that under a lock, and apply_stripe_checkout_event (shared with
// invoice payments, in ./stripe-checkout-events) records the amount it stored, not the one Stripe echoes back.

export type QuoteDepositUnavailableReason =
	| 'business_unavailable'
	| 'not_connected'
	| 'turned_off'
	| 'not_approved'
	| 'no_deposit'
	| 'already_paid';

export type QuoteDepositContext = {
	organization_id: string;
	quote_id: string;
	quote_version_id: string;
	client_id: string;
	quote_number: number;
	currency_code: string;
	available: boolean;
	unavailable_reason: QuoteDepositUnavailableReason | null;
	deposit_required_minor: number;
	livemode: boolean | null;
	stripe_account_id: string | null;
	pay_by_app: PayByAppMethods;
};

/** The part of the context the customer's browser may see: nothing here identifies the quote or the account. */
export function customerDepositView(
	context: QuoteDepositContext | null
): CustomerQuoteDepositPayment | null {
	if (!context) return null;
	const payByApp = hasAnyPayByAppMethod(context.pay_by_app) ? context.pay_by_app : null;
	if (context.unavailable_reason === 'not_connected' && !payByApp) return null;
	return {
		available: context.available,
		deposit_required_minor: context.deposit_required_minor,
		test_mode: context.livemode === false,
		pay_by_app: payByApp
	};
}

export async function getQuoteDepositContext(
	tokenHash: string
): Promise<QuoteDepositContext | null> {
	const { data, error } = await getOwnerSupabaseClient().rpc('quote_online_deposit_context', {
		supplied_token_hash: tokenHash
	});
	if (error) throw error;
	return (data as QuoteDepositContext | null) ?? null;
}

export type OpenDepositCheckoutResult =
	| { ok: true; url: string }
	| { ok: false; reason: 'unavailable' | 'stripe_rejected' | 'stripe_unavailable' };

export async function openQuoteDepositCheckout(input: {
	token: string;
	tokenHash: string;
}): Promise<OpenDepositCheckoutResult> {
	const db = getOwnerSupabaseClient();
	const { data, error } = await db.rpc('open_quote_deposit_stripe_checkout', {
		supplied_token_hash: input.tokenHash
	});
	if (error) {
		if (error.code === '23514' || error.code === 'P0404')
			return { ok: false, reason: 'unavailable' };
		throw error;
	}

	const opened = data as QuoteDepositContext & { checkout_id: string };
	const connection = await stripeClientForOrganization(opened.organization_id);
	// Disconnected between the check and now, or reconnected to another Stripe account.
	if (!connection || connection.stripeAccountId !== opened.stripe_account_id) {
		await markFailed(opened.checkout_id);
		return { ok: false, reason: 'unavailable' };
	}

	const currency = opened.currency_code.toLowerCase();
	const metadata = {
		ucrm_checkout_id: opened.checkout_id,
		ucrm_quote_id: opened.quote_id,
		ucrm_organization_id: opened.organization_id
	};
	const returnUrl = `${appOrigin()}/q/${encodeURIComponent(input.token)}`;

	let session: Stripe.Checkout.Session;
	try {
		// No payment_method_types: Stripe offers whatever the contractor switched on in their dashboard for this
		// customer's country and currency (cards, wallets, bank payments).
		session = await connection.stripe.checkout.sessions.create(
			{
				mode: 'payment',
				client_reference_id: opened.checkout_id,
				line_items: [
					{
						quantity: 1,
						price_data: {
							currency,
							unit_amount: opened.deposit_required_minor,
							product_data: { name: `Deposit for quote #${opened.quote_number}` }
						}
					}
				],
				metadata,
				payment_intent_data: {
					description: `Deposit for quote #${opened.quote_number}`,
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
