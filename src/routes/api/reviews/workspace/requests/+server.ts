import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS, validationError } from '$lib/server/api/errors';
import { reviewWorkspaceListQuerySchema } from '$lib/server/validation/reviews.schema';
import { listReviewWorkspaceRequests } from '$lib/server/reviews/requests';

// Google review campaign Part 5A: the Reviews workspace's Requests tab. The database re-checks reviews.view
// for the whole organization; a member without it gets the same refusal as any other gated page.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'reviews.view');
	if ('response' in check) return check.response;

	const params = event.url.searchParams;
	const parsed = reviewWorkspaceListQuerySchema.safeParse({
		status: params.get('status') || undefined,
		channel: params.get('channel') || undefined,
		search: params.get('search') || undefined,
		cursor: params.get('cursor') || undefined
	});
	if (!parsed.success) return validationError({ form: 'That filter is not recognised.' });

	try {
		const page = await listReviewWorkspaceRequests(
			check.auth.organization.id,
			check.auth.user.id,
			parsed.data
		);
		if (!page) {
			return json(
				{ error: 'You do not have access to review requests.' },
				{ status: 403, headers: NO_STORE_HEADERS }
			);
		}
		return json(page, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not load the review requests.', error);
		return json(
			{ error: 'Review requests could not be loaded.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};
