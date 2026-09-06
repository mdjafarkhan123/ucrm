import { env } from '$env/dynamic/private';
import {
	createPaymentReceiptAccessToken,
	paymentReceiptAccessLinkUrl
} from '$lib/server/invoices/receipt-access-links';

// The customer's door to a payment receipt. The token is generated here and only its hash ever goes to the
// database; the raw link lives exactly once, in the email the enqueue command composes. Mirrors the shipped
// invoice email link so the two never drift.
export function createPaymentReceiptEmailAccessLink() {
	const rawOrigin = env.APP_URL?.trim();
	if (!rawOrigin)
		throw new Error('APP_URL must be set before a payment receipt email can be queued.');
	const origin = new URL(rawOrigin);
	if (origin.protocol !== 'https:' && origin.hostname !== 'localhost') {
		throw new Error('APP_URL must use HTTPS outside local development.');
	}
	const { token, tokenHash } = createPaymentReceiptAccessToken();
	return { tokenHash, url: paymentReceiptAccessLinkUrl(origin.origin, token) };
}
