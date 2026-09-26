import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { ReviewRequestRefusedError, cancelReviewRequest } from '$lib/server/reviews/requests';

// Cancels a review request whose message has not started sending (a scheduled one). The database refuses
// once the customer may already have the link.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'reviews.request');
	if ('response' in check) return check.response;

	try {
		const request = await cancelReviewRequest(
			check.auth.organization.id,
			check.auth.user.id,
			event.params.id
		);
		return json(request, { headers: NO_STORE_HEADERS });
	} catch (error) {
		if (error instanceof ReviewRequestRefusedError) {
			return json({ error: error.message }, { status: error.status, headers: NO_STORE_HEADERS });
		}
		console.error('Could not cancel the review request.', error);
		return json(
			{ error: 'The review request could not be cancelled.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};
