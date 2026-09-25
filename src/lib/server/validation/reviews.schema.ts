import { z } from 'zod';
import { questionSchema } from './forms.schema';
import {
	REVIEW_EMAIL_BODY_MAX,
	REVIEW_EMAIL_SUBJECT_MAX,
	REVIEW_FEEDBACK_HEADING_MAX,
	REVIEW_FEEDBACK_INTRO_MAX,
	REVIEW_FEEDBACK_MAX_QUESTIONS,
	REVIEW_FEEDBACK_QUESTION_TYPES,
	REVIEW_SMS_BODY_MAX,
	REVIEW_STYLES,
	REVIEW_THANK_YOU_MESSAGE_MAX,
	REVIEW_THANK_YOU_TITLE_MAX,
	hasReviewLink,
	isGoogleReviewUrl,
	unknownReviewVariables
} from '$lib/reviews/settings';

// Google review campaign Part 1: the whole review setup, checked before public.save_review_settings sees it.
// Limits are twinned in $lib/reviews/settings.ts; the migration keeps only gross size backstops.

const feedbackQuestionSchema = questionSchema.refine(
	(question) => (REVIEW_FEEDBACK_QUESTION_TYPES as readonly string[]).includes(question.type),
	{ message: 'Photo questions are not available on the feedback form yet.', path: ['type'] }
);

const feedbackFormSchema = z
	.object({
		heading: z.string().trim().min(1, 'Give the form a heading.').max(REVIEW_FEEDBACK_HEADING_MAX),
		intro: z.string().trim().max(REVIEW_FEEDBACK_INTRO_MAX),
		questions: z
			.array(feedbackQuestionSchema)
			.min(1, 'Keep at least one question so the customer can tell you what happened.')
			.max(REVIEW_FEEDBACK_MAX_QUESTIONS),
		thank_you_title: z
			.string()
			.trim()
			.min(1, 'Give the thank-you screen a title.')
			.max(REVIEW_THANK_YOU_TITLE_MAX),
		thank_you_message: z.string().trim().max(REVIEW_THANK_YOU_MESSAGE_MAX)
	})
	.strict()
	.superRefine((form, ctx) => {
		const ids = form.questions.map((question) => question.id);
		if (new Set(ids).size !== ids.length) {
			ctx.addIssue({
				code: 'custom',
				path: ['questions'],
				message: 'Each question must be unique.'
			});
		}
	});

// A message may use only the review variables, and must carry the review link or it asks for nothing.
function reviewMessageText(max: number, needsLink: boolean, emptyMessage: string) {
	return z
		.string()
		.trim()
		.min(1, emptyMessage)
		.max(max)
		.superRefine((value, ctx) => {
			const unknown = unknownReviewVariables(value);
			if (unknown.length > 0) {
				ctx.addIssue({
					code: 'custom',
					message: `"{{${unknown[0]}}}" is not a variable you can use here.`
				});
			}
			if (needsLink && !hasReviewLink(value)) {
				ctx.addIssue({
					code: 'custom',
					message: 'Include the {{review_link}} variable so the customer can reply.'
				});
			}
		});
}

const smsStyleSchema = z
	.object({ body: reviewMessageText(REVIEW_SMS_BODY_MAX, true, 'Write the text message.') })
	.strict();

const emailStyleSchema = z
	.object({
		subject: reviewMessageText(REVIEW_EMAIL_SUBJECT_MAX, false, 'Write a subject line.').refine(
			(value) => !/[\r\n]/.test(value),
			'A subject line must be one line.'
		),
		body: reviewMessageText(REVIEW_EMAIL_BODY_MAX, true, 'Write the email.')
	})
	.strict();

const messageStylesSchema = z
	.object({
		default_style: z.enum(REVIEW_STYLES),
		sms: z
			.object({
				friendly: smsStyleSchema,
				professional: smsStyleSchema,
				short: smsStyleSchema
			})
			.strict(),
		email: z
			.object({
				friendly: emailStyleSchema,
				professional: emailStyleSchema,
				short: emailStyleSchema
			})
			.strict()
	})
	.strict();

export const reviewSettingsSchema = z
	.object({
		expected_revision: z.number().int().min(0),
		google_review_url: z
			.string()
			.trim()
			.transform((value) => (value === '' ? null : value))
			.nullable()
			.refine(
				(value) => value === null || isGoogleReviewUrl(value),
				'Paste the review link from your Google Business Profile. It starts with https:// and is a Google link.'
			),
		routing_enabled: z.boolean(),
		routing_google_min_rating: z.number().int().min(2).max(5),
		acknowledge_routing: z.boolean().default(false),
		feedback_form: feedbackFormSchema,
		message_styles: messageStylesSchema
	})
	.strict()
	.superRefine((input, ctx) => {
		if (input.routing_enabled && !input.google_review_url) {
			ctx.addIssue({
				code: 'custom',
				path: ['routing_enabled'],
				message: 'Add your Google review link before turning on review routing.'
			});
		}
	});

export type ReviewSettingsSchemaInput = z.infer<typeof reviewSettingsSchema>;
