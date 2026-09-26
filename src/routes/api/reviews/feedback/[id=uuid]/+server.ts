import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { reviewFeedbackStatusSchema } from '$lib/server/validation/reviews.schema';
import { ReviewRequestRefusedError, setReviewFeedbackStatus } from '$lib/server/reviews/requests';

// Google review campaign Part 5B: moves one private-feedback item through New, Contacting customer, Resolved
// and Closed. The database checks reviews.feedback again.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'reviews.feedback');
	if ('response' in check) return check.response;

	const parsed = reviewFeedbackStatusSchema.safeParse(await event.request.json().catch(() => null));
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	try {
		await setReviewFeedbackStatus(
			check.auth.organization.id,
			check.auth.user.id,
			event.params.id,
			parsed.data.status
		);
		return json({ id: event.params.id, status: parsed.data.status }, { headers: NO_STORE_HEADERS });
	} catch (error) {
		if (error instanceof ReviewRequestRefusedError) {
			return json({ error: error.message }, { status: error.status, headers: NO_STORE_HEADERS });
		}
		console.error('Could not change the private feedback status.', error);
		return json(
			{ error: 'The status could not be changed.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};
