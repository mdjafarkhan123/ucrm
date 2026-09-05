import { env } from '$env/dynamic/private';
import { createInvoiceAccessToken, invoiceAccessLinkUrl } from '$lib/server/invoices/access-links';

// The customer's door for a sent invoice. The token is generated here and only its hash ever goes to the
// database; the raw link lives exactly once, in the email the enqueue command composes. Mirrors the shipped
// quote email link so the two never drift.
export function createInvoiceEmailAccessLink() {
	const rawOrigin = env.APP_URL?.trim();
	if (!rawOrigin) throw new Error('APP_URL must be set before invoice email can be queued.');
	const origin = new URL(rawOrigin);
	if (origin.protocol !== 'https:' && origin.hostname !== 'localhost') {
		throw new Error('APP_URL must use HTTPS outside local development.');
	}
	const { token, tokenHash } = createInvoiceAccessToken();
	return { tokenHash, url: invoiceAccessLinkUrl(origin.origin, token) };
}
