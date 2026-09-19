import type Stripe from 'stripe';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { stripeClientForOrganization } from './stripe-connection';
import { applyStripeRefund } from './stripe-checkout-events';

// The contractor's "Refund" action on a Stripe-collected payment (docs/online-payments-behavior-contract.md
// §5). `reserve_stripe_payment_refund` (in Postgres) has already checked the permission, re-validated the
// amount against what this receipt has left to refund, and written a 'pending' hold row before this module
// ever talks to Stripe — this only sends the money and tells apply_stripe_refund_event what Stripe said, the
// same function the webhook calls for a refund made in Stripe's own dashboard.

export type SendStripeRefundResult =
	{ ok: true; status: 'succeeded' | 'pending' | 'failed' } | { ok: false; message: string };

type ReservedRefund = {
	refund_id: string;
	checkout_id: string;
	payment_intent_id: string | null;
	stripe_account_id: string;
	amount_minor: number;
	currency_code: string;
};

/** Sends the money for a refund `reserve_stripe_payment_refund` already reserved, then applies Stripe's own
 *  synchronous response through the same path a webhook would use. Never throws for a Stripe-side failure —
 *  the reservation stands either way, and the webhook remains the eventual source of truth if this call to
 *  Stripe never gets an answer at all (a dropped connection, a restart mid-request). */
export async function sendReservedStripeRefund(
	organizationId: string,
	reserved: ReservedRefund
): Promise<SendStripeRefundResult> {
	if (!reserved.payment_intent_id) {
		await markRefundFailed(reserved.refund_id, 'This payment has no Stripe charge to refund.');
		return { ok: false, message: 'This payment has no Stripe charge to refund.' };
	}

	const connection = await stripeClientForOrganization(organizationId);
	if (!connection || connection.stripeAccountId !== reserved.stripe_account_id) {
		await markRefundFailed(
			reserved.refund_id,
			'Stripe was disconnected before this refund could be sent.'
		);
		return {
			ok: false,
			message: 'Stripe is not connected right now, so this refund was not sent.'
		};
	}

	let refund: Stripe.Refund;
	try {
		refund = await connection.stripe.refunds.create(
			{ payment_intent: reserved.payment_intent_id, amount: reserved.amount_minor },
			{ idempotencyKey: `ucrm-refund-${reserved.refund_id}` }
		);
	} catch (stripeError) {
		const message =
			(stripeError as { message?: string } | null)?.message ?? 'Stripe rejected this refund.';
		await markRefundFailed(reserved.refund_id, message);
		return { ok: false, message };
	}

	const db = getOwnerSupabaseClient();
	// Not fatal if this write loses a race with the webhook's own upsert-by-stripe_refund_id path — both name
	// the same Stripe refund id, so apply_stripe_refund_event still finds the one row either way.
	await db
		.from('payment_stripe_refunds')
		.update({ stripe_refund_id: refund.id, updated_at: new Date().toISOString() })
		.eq('id', reserved.refund_id)
		.is('stripe_refund_id', null);

	try {
		const result = await applyStripeRefund(organizationId, `sync:${refund.id}`, 'sync', refund);
		const status =
			result.outcome === 'succeeded' || result.outcome === 'already_succeeded'
				? 'succeeded'
				: result.outcome === 'failed' || result.outcome === 'already_failed'
					? 'failed'
					: 'pending';
		return { ok: true, status };
	} catch {
		// The refund was sent; only telling UCRM about it failed just now. The webhook still will.
		return { ok: true, status: 'pending' };
	}
}

async function markRefundFailed(refundId: string, message: string) {
	const now = new Date().toISOString();
	await getOwnerSupabaseClient()
		.from('payment_stripe_refunds')
		.update({
			status: 'failed',
			failure_message: message.slice(0, 300),
			updated_at: now,
			completed_at: now
		})
		.eq('id', refundId)
		.eq('status', 'pending');
}
