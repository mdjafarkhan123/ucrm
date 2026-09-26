import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	getQuoteAccessResolverClient,
	quoteAccessIpBucketKey,
	quoteAccessTokenBucketKey,
	quoteAccessTokenHash
} from '$lib/server/quotes/access-links';
import { openQuoteDepositCheckout } from '$lib/server/payments/quote-deposit-checkout';

// The customer's Pay deposit button. Opens a Stripe Checkout session in the contractor's own Stripe account and
// returns its URL; the browser goes there. Nothing is recorded as paid here — only Stripe's signed webhook does
// that. No amount to send: the deposit is the one fixed figure the quote already asks for.
const PAY_LIMIT = { windowSeconds: 600, maxAttempts: 20 };
const PAY_TOKEN_LIMIT = { windowSeconds: 600, maxAttempts: 10 };

const MESSAGES = {
	unavailable:
		'Online payment is not available for this quote right now. Please contact the business.',
	stripe_rejected: 'The payment page could not be opened. Please contact the business.',
	stripe_unavailable: 'The payment page could not be opened. Please try again in a moment.'
} as const;

export const POST: RequestHandler = async (event) => {
	const headers = { 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' };

	const tokenHash = quoteAccessTokenHash(event.params.token);
	if (!tokenHash) return json({ error: MESSAGES.unavailable }, { status: 404, headers });

	const client = getQuoteAccessResolverClient();
	const [byAddress, byToken] = await Promise.all([
		checkRateLimit(client, {
			bucketKey: quoteAccessIpBucketKey('pay', event.getClientAddress()),
			...PAY_LIMIT
		}),
		checkRateLimit(client, {
			bucketKey: quoteAccessTokenBucketKey('pay', tokenHash),
			...PAY_TOKEN_LIMIT
		})
	]);
	if (!byAddress.allowed) return rateLimitedResponse(byAddress.retryAfterSeconds);
	if (!byToken.allowed) return rateLimitedResponse(byToken.retryAfterSeconds);

	try {
		const result = await openQuoteDepositCheckout({ token: event.params.token, tokenHash });
		if (!result.ok) {
			const status =
				result.reason === 'unavailable' ? 409 : result.reason.startsWith('stripe') ? 503 : 422;
			return json({ error: MESSAGES[result.reason], reason: result.reason }, { status, headers });
		}
		return json({ url: result.url }, { headers });
	} catch (error) {
		// Logged without the token: the URL is the customer's credential.
		console.error('An online quote deposit payment could not be started.', {
			code: (error as { code?: string } | null)?.code
		});
		return json({ error: MESSAGES.stripe_unavailable }, { status: 500, headers });
	}
};
