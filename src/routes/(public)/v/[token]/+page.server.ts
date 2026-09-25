import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { resolveReviewRequest, reviewRequestTokenHash } from '$lib/server/reviews/requests';
import type { ReviewFeedbackPageModel } from '$lib/reviews/feedback-page';

// The customer's review feedback page (Google review campaign Part 2). The token from the URL is hashed
// here and the hash goes to the one reader function the service role may call. A link that never existed,
// was cancelled, or whose client was deleted is the same plain 404, so the page cannot be used to learn
// whether a business or a customer exists.
//
// Loading the page records nothing: mail scanners and message link previews fetch URLs before any person
// sees them. The browser records the open once the page is on screen.
export const load: PageServerLoad = async ({ params, setHeaders }) => {
	setHeaders({
		'cache-control': 'no-store',
		'referrer-policy': 'no-referrer',
		'x-robots-tag': 'noindex, nofollow, noarchive'
	});

	const tokenHash = reviewRequestTokenHash(params.token);
	const request = tokenHash ? await resolveReviewRequest(tokenHash) : null;
	if (!request) error(404, 'This link is not available.');

	const model: ReviewFeedbackPageModel = {
		business: {
			name: request.business.name,
			logo_url: request.business.logo_object_key ? `/v/${params.token}/logo` : null
		},
		customer_first_name: request.customer_first_name,
		google_review_url: request.google_review_url,
		routing_enabled: request.routing_enabled,
		routing_google_min_rating: request.routing_google_min_rating,
		feedback_form: request.feedback_form,
		feedback_submitted: request.feedback_submitted
	};
	return { model };
};
