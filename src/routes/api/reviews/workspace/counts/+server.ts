import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { loadReviewWorkspaceCounts } from '$lib/server/reviews/requests';

// Google review campaign Part 5A: the four numbers above the Reviews workspace (last 30 days).
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'reviews.view');
	if ('response' in check) return check.response;

	try {
		const counts = await loadReviewWorkspaceCounts(check.auth.organization.id, check.auth.user.id);
		if (!counts) {
			return json(
				{ error: 'You do not have access to review requests.' },
				{ status: 403, headers: NO_STORE_HEADERS }
			);
		}
		return json(counts, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not load the review numbers.', error);
		return json(
			{ error: 'Review numbers could not be loaded.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};
