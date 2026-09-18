import type { RequestHandler } from './$types';
import { verifyStripeWebhook } from '$lib/server/payments/stripe-connection';

const NO_STORE = { 'cache-control': 'no-store' } as const;

// Signed notifications from a contractor's own Stripe account. The URL names the connection, whose signing
// secret proves the delivery came from Stripe. Part 2 only verifies and acknowledges: nothing takes a payment
// until Part 3 adds Checkout, which will journal and apply these events here.
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

	return new Response(JSON.stringify({ received: true }), {
		status: 200,
		headers: { ...NO_STORE, 'content-type': 'application/json' }
	});
};
