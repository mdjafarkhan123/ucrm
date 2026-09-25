import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	checkReviewRequestLimits,
	getReviewRequestClient,
	reviewRequestTokenHash
} from '$lib/server/reviews/requests';

// "The customer actually opened it." Called by the customer's own browser once the feedback page is on
// screen -- a page request proves nothing, since mail scanners and link previews fetch URLs first. It answers
// the same way whether it recorded anything or not, so a forged call cannot tell a live link from a dead one.
const NO_STORE = { 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' };

export const POST: RequestHandler = async (event) => {
	const tokenHash = reviewRequestTokenHash(event.params.token);
	if (!tokenHash) return json({ recorded: true }, { headers: NO_STORE });

	const limited = await checkReviewRequestLimits('open', event.getClientAddress(), tokenHash, {
		windowSeconds: 60,
		perAddress: 30,
		perLink: 15
	});
	if (limited) return limited;

	const { error } = await getReviewRequestClient().rpc('record_review_request_open', {
		supplied_token_hash: tokenHash
	});
	if (error) console.error('A review page open could not be recorded.', { code: error.code });

	return json({ recorded: true }, { headers: NO_STORE });
};
