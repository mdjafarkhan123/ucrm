import { error as httpError } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { resolveReviewRequest, reviewRequestTokenHash } from '$lib/server/reviews/requests';
import { streamOrganizationLogo } from '$lib/server/settings/logo';

// The business logo on a review feedback page. The object key itself never reaches the browser.
export const GET: RequestHandler = async (event) => {
	const tokenHash = reviewRequestTokenHash(event.params.token);
	const request = tokenHash ? await resolveReviewRequest(tokenHash) : null;
	const objectKey = request?.business.logo_object_key;
	if (!objectKey) throw httpError(404, 'No logo is available.');

	return streamOrganizationLogo(objectKey, event.request.headers.get('if-none-match'));
};
