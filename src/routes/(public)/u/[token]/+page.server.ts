import { fail } from '@sveltejs/kit';
import type { Actions, PageServerLoad } from './$types';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import {
	getMarketingUnsubscribeResolverClient,
	marketingUnsubscribeIpBucketKey,
	marketingUnsubscribeTokenBucketKey,
	marketingUnsubscribeTokenHash
} from '$lib/server/marketing/unsubscribe-links';

// The unsubscribe page behind the footer link of a marketing email. A stranger can walk through this door, so
// it reaches the data the long way round: the token from the URL is hashed here, the hash goes to the one
// function the service role may call, and that function decides what a customer may see — the business name,
// their own address, and nothing else.
//
// Opening the page records nothing. Company mail scanners, link-preview bots and security appliances fetch
// every URL in an email before any person sees it, so an unsubscribe that happened on load would silently cut
// customers off from mail they still want. The visible click on this page, and a mailbox provider's own
// one-click POST next door, are the only two things that write.
//
// Every way of failing looks identical — unknown token, a deleted email address, a closed organization — so
// the page cannot be used to find out whether an address exists anywhere in UCRM.

type UnsubscribeTarget = {
	business_name: string | null;
	email: string;
	already_unsubscribed: boolean;
};

// Generous, because a whole office can share one address and a person may reload while reading.
const VIEW_LIMIT = { windowSeconds: 60, maxAttempts: 30 };
const VIEW_TOKEN_LIMIT = { windowSeconds: 60, maxAttempts: 15 };
const ACTION_LIMIT = { windowSeconds: 60, maxAttempts: 10 };
const ACTION_TOKEN_LIMIT = { windowSeconds: 60, maxAttempts: 5 };

const noStore = {
	'cache-control': 'no-store',
	// The URL is the credential. No referrer means it cannot ride along to wherever the customer clicks next,
	// and no indexing means it cannot end up in a search result.
	'referrer-policy': 'no-referrer',
	'x-robots-tag': 'noindex, nofollow, noarchive'
};

export const load: PageServerLoad = async ({ params, setHeaders, getClientAddress }) => {
	setHeaders(noStore);

	const tokenHash = marketingUnsubscribeTokenHash(params.token);
	if (!tokenHash) return { target: null, throttled: false };

	const client = getMarketingUnsubscribeResolverClient();

	// A limiter that cannot answer lets the page through rather than showing a working link as broken.
	try {
		const [byAddress, byToken] = await Promise.all([
			checkRateLimit(client, {
				bucketKey: marketingUnsubscribeIpBucketKey('view', getClientAddress()),
				...VIEW_LIMIT
			}),
			checkRateLimit(client, {
				bucketKey: marketingUnsubscribeTokenBucketKey('view', tokenHash),
				...VIEW_TOKEN_LIMIT
			})
		]);
		if (!byAddress.allowed || !byToken.allowed) return { target: null, throttled: true };
	} catch {
		console.error('The unsubscribe rate limiter did not answer; the page was allowed through.');
	}

	const { data, error } = await client.rpc('resolve_client_marketing_unsubscribe_link', {
		supplied_token_hash: tokenHash
	});

	// Deliberately not logged with the token or the reason. A failure here is either a broken link or somebody
	// guessing, and neither should write a customer's URL into a log file.
	if (error || !data) return { target: null, throttled: false };

	return { target: data as unknown as UnsubscribeTarget, throttled: false };
};

export const actions: Actions = {
	// The confirm button. Progressive enhancement is not used: this has to work in whatever browser the
	// customer's mail app happens to open, including one with JavaScript switched off.
	//
	// The no-store headers are not set here. A form post re-runs `load` before the page is rendered, and
	// SvelteKit refuses a header that has already been set once in the same request.
	default: async ({ params, getClientAddress }) => {
		const tokenHash = marketingUnsubscribeTokenHash(params.token);
		if (!tokenHash) return fail(400, { done: false });

		const client = getMarketingUnsubscribeResolverClient();

		try {
			const [byAddress, byToken] = await Promise.all([
				checkRateLimit(client, {
					bucketKey: marketingUnsubscribeIpBucketKey('confirm', getClientAddress()),
					...ACTION_LIMIT
				}),
				checkRateLimit(client, {
					bucketKey: marketingUnsubscribeTokenBucketKey('confirm', tokenHash),
					...ACTION_TOKEN_LIMIT
				})
			]);
			if (!byAddress.allowed || !byToken.allowed) return fail(429, { done: false });
		} catch {
			// Same trade as the one-click endpoint: a broken limiter must not swallow a real unsubscribe.
			console.error(
				'The unsubscribe rate limiter did not answer; the request was allowed through.'
			);
		}

		const { data, error } = await client.rpc('record_client_marketing_unsubscribe', {
			supplied_token_hash: tokenHash,
			supplied_evidence: { recorded_via: 'unsubscribe_page' }
		});
		if (error || !data) return fail(400, { done: false });

		// Already unsubscribed is a success here too: the customer pressed a button that says stop, and it
		// has stopped. Telling them anything else would just invite a second, worried click.
		return { done: true, target: data as unknown as UnsubscribeTarget };
	}
};
