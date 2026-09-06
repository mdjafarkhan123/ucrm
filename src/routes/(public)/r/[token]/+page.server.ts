import type { PageServerLoad } from './$types';
import {
	getPaymentReceiptAccessResolverClient,
	paymentReceiptAccessTokenHash
} from '$lib/server/invoices/receipt-access-links';
import type { CustomerPaymentReceipt } from '$lib/invoices/customer-receipt';

// The customer's receipt for one recorded payment. Like the invoice token page, this is a door a stranger can
// walk through, and it reaches the data the long way round: the token from the URL is hashed here, the hash
// goes to the one function the service role may call, and that function decides what a customer may see.
// Nothing is filtered in the browser, because anything sent to the browser can be read back out of it.
//
// Every way of failing looks the same — unknown token, revoked, expired, or a payment that is not a plain
// recorded receipt — so the page cannot be used to find out whether a payment, a client or an organization
// exists. Unlike an invoice link there is no separate "expired" message: a payment is immutable once
// recorded, so a receipt link is only ever closed on purpose, and the answer is always "ask for a new one".
//
// Loading the page records nothing. Jobber's receipt has no view tracking, and neither does ours: mail
// scanners and chat link previews fetch URLs before any person sees them.
export const load: PageServerLoad = async ({ params, setHeaders }) => {
	setHeaders({
		'cache-control': 'no-store',
		// The URL is the credential. No referrer means it cannot ride along to anywhere the customer clicks
		// next, and no indexing means it cannot end up in a search result.
		'referrer-policy': 'no-referrer',
		'x-robots-tag': 'noindex, nofollow, noarchive'
	});

	const tokenHash = paymentReceiptAccessTokenHash(params.token);
	if (!tokenHash) return { document: null };

	const { data, error } = await getPaymentReceiptAccessResolverClient().rpc(
		'resolve_payment_receipt_access_link',
		{ supplied_token_hash: tokenHash }
	);

	// Deliberately not logged with the token or the reason. A failure here is either a broken link or somebody
	// guessing, and neither should write a customer's URL into a log file.
	if (error || !data) return { document: null };

	return { document: data as unknown as CustomerPaymentReceipt };
};
