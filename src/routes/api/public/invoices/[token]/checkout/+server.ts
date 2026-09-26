import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	getInvoiceAccessResolverClient,
	invoiceAccessIpBucketKey,
	invoiceAccessTokenBucketKey,
	invoiceAccessTokenHash
} from '$lib/server/invoices/access-links';
import { openInvoiceCheckout } from '$lib/server/payments/invoice-checkout';
import { invoiceCheckoutSchema } from '$lib/server/validation/invoices.schema';

// The customer's Pay button. Opens a Stripe Checkout session in the contractor's own Stripe account and returns
// its URL; the browser goes there. Nothing is recorded as paid here — only Stripe's signed webhook does that.
const PAY_LIMIT = { windowSeconds: 600, maxAttempts: 20 };
const PAY_TOKEN_LIMIT = { windowSeconds: 600, maxAttempts: 10 };

const MESSAGES = {
	unavailable:
		'Online payment is not available for this invoice right now. Please contact the business.',
	amount: 'Please check the amount. It cannot be more than what is still owed.',
	tip: 'That tip could not be added. Please try a different amount.',
	stripe_rejected:
		'The payment page could not be opened for this amount. Please contact the business.',
	stripe_unavailable: 'The payment page could not be opened. Please try again in a moment.'
} as const;

export const POST: RequestHandler = async (event) => {
	const headers = { 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' };

	const tokenHash = invoiceAccessTokenHash(event.params.token);
	if (!tokenHash) return json({ error: MESSAGES.unavailable }, { status: 404, headers });

	const client = getInvoiceAccessResolverClient();
	const [byAddress, byToken] = await Promise.all([
		checkRateLimit(client, {
			bucketKey: invoiceAccessIpBucketKey('pay', event.getClientAddress()),
			...PAY_LIMIT
		}),
		checkRateLimit(client, {
			bucketKey: invoiceAccessTokenBucketKey('pay', tokenHash),
			...PAY_TOKEN_LIMIT
		})
	]);
	if (!byAddress.allowed) return rateLimitedResponse(byAddress.retryAfterSeconds);
	if (!byToken.allowed) return rateLimitedResponse(byToken.retryAfterSeconds);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: MESSAGES.amount }, { status: 422, headers });
	}
	const parsed = invoiceCheckoutSchema.safeParse(body);
	if (!parsed.success) return json({ error: MESSAGES.amount }, { status: 422, headers });

	try {
		const result = await openInvoiceCheckout({
			token: event.params.token,
			tokenHash,
			amountMinor: parsed.data.amount_minor,
			tipMinor: parsed.data.tip_minor
		});
		if (!result.ok) {
			const status =
				result.reason === 'unavailable' ? 409 : result.reason.startsWith('stripe') ? 503 : 422;
			return json({ error: MESSAGES[result.reason], reason: result.reason }, { status, headers });
		}
		return json({ url: result.url }, { headers });
	} catch (error) {
		// Logged without the token: the URL is the customer's credential.
		console.error('An online invoice payment could not be started.', {
			code: (error as { code?: string } | null)?.code
		});
		return json({ error: MESSAGES.stripe_unavailable }, { status: 500, headers });
	}
};
