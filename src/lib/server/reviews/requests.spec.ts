import { describe, expect, it } from 'vitest';
import {
	createReviewRequestToken,
	fillReviewMessage,
	renderReviewEmailHtml,
	reviewRequestTokenHash
} from './requests';
import {
	reviewFeedbackSubmissionSchema,
	reviewGoogleChoiceSchema,
	reviewRequestCreateSchema
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

describe('manual review request messages', () => {
	const link = 'https://app.example.com/v/abc_DEF-123';

	it('fills every review variable and leaves unknown text alone', () => {
		expect(
			fillReviewMessage(
				'Hi {{customer_first_name}}, from {{business_name}}: {{review_link}} {{x}}',
				{
					customer_first_name: 'Sam',
					business_name: 'Raad LTD',
					review_link: link
				}
			)
		).toBe(`Hi Sam, from Raad LTD: ${link} {{x}}`);
	});

	it('escapes the email text and makes only the review link clickable', () => {
		const html = renderReviewEmailHtml(`Hi <b>Sam</b> & co\nTell us: ${link}`, link);
		expect(html).toBe(
			`<p>Hi &lt;b&gt;Sam&lt;/b&gt; &amp; co<br>Tell us: <a href="${link}">${link}</a></p>`
		);
		expect(html).toContain(link);
	});

	const valid = {
		client_id: '6b1f3c1e-8f0a-4c52-9d3e-2a7f5b1c0e01',
		job_id: null,
		channel: 'sms',
		style: 'friendly',
		contact_method_id: '6b1f3c1e-8f0a-4c52-9d3e-2a7f5b1c0e02',
		body: 'Thanks! {{review_link}}',
		idempotency_key: 'a1b2c3d4e5f6'
	};

	it('accepts a text message that carries the review link', () => {
		expect(reviewRequestCreateSchema.safeParse(valid).success).toBe(true);
	});

	it('refuses a message without the link, an email without a subject, and a past send time', () => {
		expect(reviewRequestCreateSchema.safeParse({ ...valid, body: 'Thanks!' }).success).toBe(false);
		expect(
			reviewRequestCreateSchema.safeParse({ ...valid, channel: 'email', subject: '' }).success
		).toBe(false);
		expect(
			reviewRequestCreateSchema.safeParse({ ...valid, send_at: '2020-01-01T10:00:00Z' }).success
		).toBe(false);
	});
});
