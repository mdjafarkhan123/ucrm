import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	getInvoiceAccessResolverClient,
	invoiceAccessIpBucketKey,
	invoiceAccessTokenBucketKey,
	invoiceAccessTokenHash
} from '$lib/server/invoices/access-links';

// "Somebody actually looked at it." Called by the customer's own browser once the document is on screen, which
// is the only moment that means what staff think it means. A page request proves nothing: mail scanners, chat
// link previews and security appliances all fetch a URL before any person sees it.
//
// It answers the same way whether it recorded anything or not. A forged call with a dead token must not be a
// way to find out that the token is dead.
const VIEW_LIMIT = { windowSeconds: 60, maxAttempts: 30 };
const VIEW_TOKEN_LIMIT = { windowSeconds: 60, maxAttempts: 15 };

export const POST: RequestHandler = async (event) => {
	const noStore = { 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' };

	const tokenHash = invoiceAccessTokenHash(event.params.token);
	if (!tokenHash) return json({ recorded: false }, { headers: noStore });

	const client = getInvoiceAccessResolverClient();

	// Checked together, not one then the other: the customer is waiting on this call before their page settles,
	// and the usual answer is that both are fine.
	const [byAddress, byToken] = await Promise.all([
		checkRateLimit(client, {
			bucketKey: invoiceAccessIpBucketKey('view', event.getClientAddress()),
			...VIEW_LIMIT
		}),
		checkRateLimit(client, {
			bucketKey: invoiceAccessTokenBucketKey('view', tokenHash),
			...VIEW_TOKEN_LIMIT
		})
	]);
	if (!byAddress.allowed) return rateLimitedResponse(byAddress.retryAfterSeconds);
	if (!byToken.allowed) return rateLimitedResponse(byToken.retryAfterSeconds);

	const { error } = await client.rpc('record_invoice_link_view', {
		supplied_token_hash: tokenHash
	});

	// Nothing the customer can do about it and nothing they need to know: their invoice is already on the
	// screen in front of them. Logged without the token.
	if (error) console.error('An invoice view could not be recorded.', { code: error.code });

	return json({ recorded: true }, { headers: noStore });
};
