import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { Json } from '$lib/database.types';
import { validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { reviewFeedbackSubmissionSchema } from '$lib/server/validation/reviews.schema';
import { buildQuestionAnswersSchema } from '$lib/server/validation/public-forms.schema';
import {
	checkReviewRequestLimits,
	getReviewRequestClient,
	resolveReviewRequest,
	reviewRequestTokenHash
} from '$lib/server/reviews/requests';

// The customer's private feedback. The link is the credential and each request takes one submission, so a
// per-address and per-link limit is the whole spam defence; there is no "are you human" check to get past.
// Answers are checked against the organization's feedback form as it stands now, and stored beside a copy
// of those questions.
const NO_STORE = { 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' };
const NOT_AVAILABLE = { error: 'This link is not available.' };

export const POST: RequestHandler = async (event) => {
	const tokenHash = reviewRequestTokenHash(event.params.token);
	if (!tokenHash) return json(NOT_AVAILABLE, { status: 404, headers: NO_STORE });

	const limited = await checkReviewRequestLimits('feedback', event.getClientAddress(), tokenHash, {
		windowSeconds: 900,
		perAddress: 10,
		perLink: 5
	});
	if (limited) return limited;

	const parsedBody = reviewFeedbackSubmissionSchema.safeParse(
		await event.request.json().catch(() => null)
	);
	if (!parsedBody.success) return validationError(zodFieldErrors(parsedBody.error));

	const request = await resolveReviewRequest(tokenHash);
	if (!request) return json(NOT_AVAILABLE, { status: 404, headers: NO_STORE });

	const questions = request.feedback_form.questions;
	const parsedAnswers = buildQuestionAnswersSchema(questions).safeParse(parsedBody.data.answers);
	if (!parsedAnswers.success) {
		return json(
			{
				error: 'Please answer the questions marked with a star.',
				field_errors: zodFieldErrors(parsedAnswers.error)
			},
			{ status: 422, headers: NO_STORE }
		);
	}

	const { data, error } = await getReviewRequestClient().rpc('submit_review_feedback', {
		supplied_token_hash: tokenHash,
		supplied_rating: parsedBody.data.rating as number,
		supplied_questions: questions as unknown as Json,
		supplied_answers: parsedAnswers.data as Json
	});
	if (error) {
		console.error('Private review feedback could not be saved.', { code: error.code });
		return json(
			{ error: 'We could not send your feedback. Please try again.' },
			{ status: 500, headers: NO_STORE }
		);
	}
	if (!data) return json(NOT_AVAILABLE, { status: 404, headers: NO_STORE });

	return json({ submitted: true }, { headers: NO_STORE });
};
