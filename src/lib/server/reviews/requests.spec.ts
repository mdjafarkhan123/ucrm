import { describe, expect, it } from 'vitest';
import { createReviewRequestToken, reviewRequestTokenHash } from './requests';
import {
	reviewFeedbackSubmissionSchema,
	reviewGoogleChoiceSchema
} from '$lib/server/validation/reviews.schema';
import { buildQuestionAnswersSchema } from '$lib/server/validation/public-forms.schema';
import { DEFAULT_REVIEW_FEEDBACK_FORM } from '$lib/reviews/settings';

describe('review request links', () => {
	it('hashes a made token to the same value the page will look up', () => {
		const { token, tokenHash } = createReviewRequestToken();
		expect(reviewRequestTokenHash(token)).toBe(tokenHash);
		expect(tokenHash).toMatch(/^\\x[0-9a-f]{64}$/);
	});

	it('refuses a token of the wrong shape without hashing it', () => {
		expect(reviewRequestTokenHash(undefined)).toBeNull();
		expect(reviewRequestTokenHash('short')).toBeNull();
		expect(reviewRequestTokenHash('a'.repeat(42) + '!')).toBeNull();
	});
});

describe('what the feedback page sends', () => {
	it('takes a 1-5 star rating or none', () => {
		expect(reviewGoogleChoiceSchema.parse({})).toEqual({ rating: null });
		expect(reviewGoogleChoiceSchema.safeParse({ rating: 5 }).success).toBe(true);
		expect(reviewGoogleChoiceSchema.safeParse({ rating: 0 }).success).toBe(false);
		expect(reviewGoogleChoiceSchema.safeParse({ rating: 2.5 }).success).toBe(false);
		expect(reviewFeedbackSubmissionSchema.safeParse({ rating: 6, answers: {} }).success).toBe(
			false
		);
	});

	it('refuses anything beyond rating and answers', () => {
		expect(reviewFeedbackSubmissionSchema.safeParse({ answers: {}, request_id: 'x' }).success).toBe(
			false
		);
	});

	it('checks answers against the default feedback questions', () => {
		const schema = buildQuestionAnswersSchema(DEFAULT_REVIEW_FEEDBACK_FORM.questions);
		const [whatHappened, contactMe] = DEFAULT_REVIEW_FEEDBACK_FORM.questions;
		expect(schema.safeParse({ [whatHappened.id]: 'Late', [contactMe.id]: true }).success).toBe(
			true
		);
		expect(schema.safeParse({ [whatHappened.id]: '   ', [contactMe.id]: true }).success).toBe(
			false
		);
		expect(schema.safeParse({ [whatHappened.id]: 'Late' }).success).toBe(false);
	});
});
