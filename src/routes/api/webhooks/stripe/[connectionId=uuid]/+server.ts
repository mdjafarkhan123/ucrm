import type { RequestHandler } from './$types';
import { verifyStripeWebhook } from '$lib/server/payments/stripe-connection';
import { handleStripeEvent } from '$lib/server/payments/stripe-checkout-events';

const NO_STORE = { 'cache-control': 'no-store' } as const;

// Signed notifications from a contractor's own Stripe account. The URL names the connection, whose signing
// secret proves the delivery came from Stripe, and whose organization is the only one the event may touch.
// Every business outcome (already applied, unknown session, overpayment) is acknowledged with 200; only our
// own failures return 500 so Stripe retries them. Redelivery is harmless: events are journaled by id.
export const POST: RequestHandler = async ({ request, params }) => {
	const signature = request.headers.get('stripe-signature');
	if (!signature) return new Response(null, { status: 400, headers: NO_STORE });

	// Stripe signs the exact raw body, so it is read as text and never re-serialized.
	const payload = await request.text();

	let verified;
	try {
		verified = await verifyStripeWebhook({ connectionId: params.connectionId, payload, signature });
	} catch {
		// Our database failed, not the sender: ask Stripe to retry.
		return new Response(null, { status: 500, headers: NO_STORE });
	}

	// Unknown connection or bad signature. Never say which.
	if (!verified) return new Response(null, { status: 400, headers: NO_STORE });

	try {
		await handleStripeEvent(verified.organizationId, verified.event);
	} catch (error) {
		console.error('A Stripe event could not be applied; Stripe will retry it.', {
			type: verified.event.type,
			code: (error as { code?: string } | null)?.code
		});
		return new Response(null, { status: 500, headers: NO_STORE });
	}

	return new Response(JSON.stringify({ received: true }), {
		status: 200,
		headers: { ...NO_STORE, 'content-type': 'application/json' }
	});
};
