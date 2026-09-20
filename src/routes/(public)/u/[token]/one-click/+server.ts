import type { RequestHandler } from './$types';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import {
	getMarketingUnsubscribeResolverClient,
	marketingUnsubscribeIpBucketKey,
	marketingUnsubscribeTokenBucketKey,
	marketingUnsubscribeTokenHash
} from '$lib/server/marketing/unsubscribe-links';

// The address in the `List-Unsubscribe` header, for the unsubscribe button Gmail, Apple Mail and Outlook draw
// on the message themselves (RFC 8058). The mailbox provider POSTs here after the person confirms in their own
// interface, so there is nothing left for us to confirm: this unsubscribes immediately and answers in one
// plain response, with no redirect, which the RFC forbids here.
//
// It lives one path below the page instead of on it because a normal form submission is answered with a 303,
// and that is precisely what a provider must not receive.
const ONE_CLICK_LIMIT = { windowSeconds: 60, maxAttempts: 20 };
const ONE_CLICK_TOKEN_LIMIT = { windowSeconds: 60, maxAttempts: 10 };

const headers = {
	'content-type': 'text/plain; charset=utf-8',
	'cache-control': 'no-store',
	'referrer-policy': 'no-referrer',
	'x-robots-tag': 'noindex, nofollow, noarchive'
};

// Every outcome that is not a rate limit answers identically. A provider retrying, a forwarded copy of the
// email, an address already unsubscribed and a token that no longer resolves all mean the same thing to the
// person who pressed the button — no more marketing email — and none of them should turn this endpoint into a
// way of testing whether an address exists.
const accepted = () => new Response('You have been unsubscribed.\n', { status: 200, headers });

export const POST: RequestHandler = async ({ params, request, getClientAddress }) => {
	// Read and discard the body. RFC 8058 has the provider send `List-Unsubscribe=One-Click` in it, but the
	// token in the URL is what authorizes this, and refusing a provider whose body differs would leave a real
	// person subscribed after they asked to leave — which costs a spam complaint, the worst outcome here.
	await request.text().catch(() => '');

	const tokenHash = marketingUnsubscribeTokenHash(params.token);
	if (!tokenHash) return accepted();

	const client = getMarketingUnsubscribeResolverClient();

	// A provider that is being throttled must be told to come back, not told it succeeded, or the person's
	// request is lost. Retry-After is honored by the mailbox providers that implement this header.
	//
	// A limiter that cannot answer at all lets the request through instead of blocking it. Dropping a real
	// unsubscribe is the worse failure by a long way: it earns a spam complaint, which damages deliverability
	// for every contractor on the shared sending reputation.
	try {
		const [byAddress, byToken] = await Promise.all([
			checkRateLimit(client, {
				bucketKey: marketingUnsubscribeIpBucketKey('one_click', getClientAddress()),
				...ONE_CLICK_LIMIT
			}),
			checkRateLimit(client, {
				bucketKey: marketingUnsubscribeTokenBucketKey('one_click', tokenHash),
				...ONE_CLICK_TOKEN_LIMIT
			})
		]);
		if (!byAddress.allowed || !byToken.allowed) {
			const retryAfter = Math.max(byAddress.retryAfterSeconds, byToken.retryAfterSeconds, 1);
			return new Response('Too many attempts. Please try again shortly.\n', {
				status: 429,
				headers: { ...headers, 'Retry-After': String(retryAfter) }
			});
		}
	} catch {
		console.error('The unsubscribe rate limiter did not answer; the request was allowed through.');
	}

	const { error } = await client.rpc('record_client_marketing_unsubscribe', {
		supplied_token_hash: tokenHash,
		supplied_evidence: { recorded_via: 'one_click_header' }
	});

	// Logged without the token: a customer's unsubscribe URL must never reach a log file.
	if (error) console.error('A one-click unsubscribe could not be recorded.', { code: error.code });

	return accepted();
};
