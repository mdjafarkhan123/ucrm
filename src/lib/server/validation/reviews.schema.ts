import { z } from 'zod';
import { questionSchema } from './forms.schema';
import {
	REVIEW_EMAIL_BODY_MAX,
	REVIEW_EMAIL_SUBJECT_MAX,
	REVIEW_FEEDBACK_HEADING_MAX,
	REVIEW_FEEDBACK_INTRO_MAX,
	REVIEW_FEEDBACK_MAX_QUESTIONS,
	REVIEW_FEEDBACK_QUESTION_TYPES,
	REVIEW_CHANNELS,
	REVIEW_FIRST_SEND_DELAY_MAX,
	REVIEW_FIRST_SEND_UNITS,
	REVIEW_REMINDERS_MAX,
	REVIEW_REMINDER_WAIT_MAX_DAYS,
	REVIEW_REMINDER_WAIT_MIN_DAYS,
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

const messageSetShape = {
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
};

const messageStylesSchema = z
	.object({ default_style: z.enum(REVIEW_STYLES), ...messageSetShape })
	.strict();

// Part 4A: when the first message goes and the reminders that follow it.
const requestPlanSchema = z
	.object({
		first_send_delay: z
			.object({
				amount: z.number().int().min(0),
				unit: z.enum(REVIEW_FIRST_SEND_UNITS)
			})
			.strict()
			.refine((delay) => delay.amount <= REVIEW_FIRST_SEND_DELAY_MAX[delay.unit], {
				message: 'Choose a delay of up to 72 hours or 30 days.',
				path: ['amount']
			}),
		reminders: z
			.array(
				z
					.object({
						id: z.uuid(),
						wait_days: z
							.number()
							.int()
							.min(REVIEW_REMINDER_WAIT_MIN_DAYS, 'Wait at least 1 day.')
							.max(REVIEW_REMINDER_WAIT_MAX_DAYS, 'Wait no more than 60 days.'),
						messages: z.object(messageSetShape).strict()
					})
					.strict()
			)
			.max(REVIEW_REMINDERS_MAX, `Send at most ${REVIEW_REMINDERS_MAX} reminders.`)
	})
	.strict()
	.superRefine((plan, ctx) => {
		const ids = plan.reminders.map((reminder) => reminder.id);
		if (new Set(ids).size !== ids.length) {
			ctx.addIssue({
				code: 'custom',
				path: ['reminders'],
				message: 'Each reminder must be unique.'
			});
		}
	});

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
		message_styles: messageStylesSchema,
		request_plan: requestPlanSchema
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

// Google review campaign Part 2: what the customer's feedback page sends. Answers are checked again, per
// question, against the organization's current feedback form in the route.
const starRatingSchema = z.number().int().min(1).max(5).nullable().default(null);

export const reviewGoogleChoiceSchema = z.object({ rating: starRatingSchema }).strict();

export const reviewFeedbackSubmissionSchema = z
	.object({
		rating: starRatingSchema,
		answers: z.record(z.string(), z.unknown()).default({})
	})
	.strict();

// Google review campaign Part 3: a manual review request as the panel sends it. The message is the style's
// text as the contractor edited it, variables unfilled; the server fills them and makes the link.
export const reviewRequestContextQuerySchema = z.union([
	z.object({ job_id: z.uuid(), client_id: z.undefined() }),
	z.object({ client_id: z.uuid(), job_id: z.undefined() })
]);

export const reviewRequestCreateSchema = z
	.object({
		client_id: z.uuid(),
		job_id: z.uuid().nullable(),
		channel: z.enum(REVIEW_CHANNELS),
		style: z.enum(REVIEW_STYLES),
		contact_method_id: z.uuid('Choose who to send it to.'),
		subject: z.string().default(''),
		body: z.string(),
		send_at: z.iso
			.datetime({ offset: true })
			.nullable()
			.default(null)
			.refine(
				(value) => {
					if (value === null) return true;
					const at = Date.parse(value);
					return at > Date.now() && at <= Date.now() + 90 * 24 * 60 * 60 * 1000;
				},
				{ message: 'Choose a time in the next 90 days.' }
			),
		idempotency_key: z.string().trim().min(8).max(200)
	})
	.strict()
	.superRefine((input, ctx) => {
		const body =
			input.channel === 'sms'
				? reviewMessageText(REVIEW_SMS_BODY_MAX, true, 'Write the text message.')
				: reviewMessageText(REVIEW_EMAIL_BODY_MAX, true, 'Write the email.');
		for (const issue of body.safeParse(input.body).error?.issues ?? []) {
			ctx.addIssue({ code: 'custom', path: ['body'], message: issue.message });
		}
		if (input.channel === 'email') {
			const subject = emailStyleSchema.shape.subject.safeParse(input.subject);
			for (const issue of subject.error?.issues ?? []) {
				ctx.addIssue({ code: 'custom', path: ['subject'], message: issue.message });
			}
		}
	});

export type ReviewRequestCreateInput = z.infer<typeof reviewRequestCreateSchema>;
