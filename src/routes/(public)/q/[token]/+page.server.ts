import type { PageServerLoad } from './$types';
import {
	getQuoteAccessResolverClient,
	quoteAccessTokenHash
} from '$lib/server/quotes/access-links';
import type { CustomerQuoteDocument } from '$lib/quotes/customer-document';

// The customer's copy. This is the only place in the app a stranger can reach quote data, and it reaches
// it the long way round: the token from the URL is hashed here, the hash goes to the one function the
// service role may call, and that function decides what a customer is allowed to see. Nothing on this
// page is filtered in the browser, because anything sent to the browser can be read back out of it.
//
// Every way of failing looks the same but one. An unknown token, a revoked one, one for a version that
// has since been replaced, or a quote that was archived all come back as `document: null`, so the page
// cannot be used to find out whether a quote, a client or an organization exists. A link that simply ran
// out says so, because that person needs to know to ask for a new one and the fact that their own link
// expired tells them nothing they did not already have.
//
// Loading the page records nothing. Mail scanners and chat link previews fetch URLs before any person
// sees them, so the view is recorded by the browser once the document is actually drawn.
export const load: PageServerLoad = async ({ params, setHeaders }) => {
	setHeaders({
		'cache-control': 'no-store',
		// The URL is the credential. No referrer means it cannot ride along to anywhere the customer
		// clicks next, and no indexing means it cannot end up in a search result.
		'referrer-policy': 'no-referrer',
		'x-robots-tag': 'noindex, nofollow, noarchive'
	});

	const tokenHash = quoteAccessTokenHash(params.token);
	if (!tokenHash) return { document: null, expired: false };

	const { data, error } = await getQuoteAccessResolverClient().rpc('resolve_quote_access_link', {
		supplied_token_hash: tokenHash
	});

	// Deliberately not logged with the token or the reason. A failure here is either a broken link or
	// somebody guessing, and neither should write a customer's URL into a log file.
	if (error || !data) return { document: null, expired: false };

	if (typeof data === 'object' && 'expired' in data) return { document: null, expired: true };

	return { document: data as unknown as CustomerQuoteDocument, expired: false };
};
