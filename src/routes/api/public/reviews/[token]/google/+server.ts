import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { reviewGoogleChoiceSchema } from '$lib/server/validation/reviews.schema';
import {
	checkReviewRequestLimits,
	getReviewRequestClient,
	reviewRequestTokenHash
} from '$lib/server/reviews/requests';

// The customer chose Google. The browser sends this on its way out (keepalive) and goes to Google whatever
// the answer, so a slow or failed record never stands between a customer and their review. Answers the same
// way for a live link and a dead one.
const NO_STORE = { 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' };

export const POST: RequestHandler = async (event) => {
	const tokenHash = reviewRequestTokenHash(event.params.token);
	if (!tokenHash) return json({ recorded: true }, { headers: NO_STORE });

	const parsed = reviewGoogleChoiceSchema.safeParse(await event.request.json().catch(() => null));
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const limited = await checkReviewRequestLimits('google', event.getClientAddress(), tokenHash, {
		windowSeconds: 60,
		perAddress: 20,
		perLink: 10
	});
	if (limited) return limited;

	const { error } = await getReviewRequestClient().rpc('record_review_request_google', {
		supplied_token_hash: tokenHash,
		supplied_rating: parsed.data.rating as number
	});
	if (error) console.error('A Google review choice could not be recorded.', { code: error.code });

	return json({ recorded: true }, { headers: NO_STORE });
};
