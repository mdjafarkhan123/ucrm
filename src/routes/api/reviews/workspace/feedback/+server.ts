import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS, validationError } from '$lib/server/api/errors';
import { reviewFeedbackListQuerySchema } from '$lib/server/validation/reviews.schema';
import { listReviewFeedback } from '$lib/server/reviews/requests';

// Google review campaign Part 5B: the Reviews workspace's Private feedback tab. The database re-checks
// reviews.feedback for the whole organization, so a member without it never sees a customer's words.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'reviews.feedback');
	if ('response' in check) return check.response;

	const params = event.url.searchParams;
	const parsed = reviewFeedbackListQuerySchema.safeParse({
		status: params.get('status') || undefined,
		search: params.get('search') || undefined,
		cursor: params.get('cursor') || undefined
	});
	if (!parsed.success) return validationError({ form: 'That filter is not recognised.' });

	try {
		const page = await listReviewFeedback(
			check.auth.organization.id,
			check.auth.user.id,
			parsed.data
		);
		if (!page) {
			return json(
				{ error: 'You do not have access to private feedback.' },
				{ status: 403, headers: NO_STORE_HEADERS }
			);
		}
		return json(page, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not load the private feedback.', error);
		return json(
			{ error: 'Private feedback could not be loaded.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};
