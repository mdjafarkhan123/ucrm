import { z } from 'zod';
import {
	BOOKING_ARRIVAL_WINDOW_MAX_MINUTES,
	BOOKING_BUFFER_MAX_MINUTES,
	BOOKING_MAX_SERVICES,
	BOOKING_MIN_NOTICE_MAX_MINUTES,
	BOOKING_SLOT_INTERVAL_MAX_MINUTES,
	BOOKING_SLOT_INTERVAL_MIN_MINUTES,
	BOOKING_VISIT_DURATION_MAX_MINUTES,
	BOOKING_VISIT_DURATION_MIN_MINUTES,
	FORM_CONFIRMATION_MESSAGE_MAX,
	FORM_CONFIRMATION_TITLE_MAX,
	FORM_DESCRIPTION_MAX,
	FORM_MAX_OPTIONS,
	FORM_MAX_PHOTOS,
	FORM_MAX_QUESTIONS,
	FORM_MAX_SECTIONS,
	FORM_NAME_MAX,
	FORM_OPTION_MAX,
	FORM_OUTCOMES,
	FORM_QUESTION_HELP_MAX,
	FORM_QUESTION_LABEL_MAX,
	FORM_QUESTION_TYPES,
	FORM_REDIRECT_URL_MAX,
	FORM_SECTION_TITLE_MAX,
	FORM_TITLE_MAX,
	isChoiceQuestion,
	type FormQuestionType
} from '$lib/forms/types';

// The public shape of a request form, validated before it reaches the database (CLAUDE.md rule 12). Every
// limit here has a twin in $lib/forms/types.ts and a gross backstop in the migration; the point of this file
// is a sentence about the field a person typed, not a constraint name. Booking rules (assessment/job forms)
// have their own schema further down.

const contactName = z.object({ required: z.boolean() });
const contactContactable = z.object({
	shown: z.boolean(),
	required: z.boolean(),
	marketing_consent: z.boolean()
});
const contactPlain = z.object({ shown: z.boolean(), required: z.boolean() });

const contactBlockSchema = z
	.object({
		name: contactName,
		email: contactContactable,
		phone: contactContactable,
		company: contactPlain,
		address: contactPlain
	})
	.superRefine((contact, ctx) => {
		// A request form with no way to reach the customer back cannot do its job.
		if (!contact.email.shown && !contact.phone.shown) {
			ctx.addIssue({
				code: 'custom',
				path: ['email', 'shown'],
				message: 'Show at least an email or a phone field so customers can be contacted.'
			});
		}
		// A field the customer can never see cannot be required.
		for (const key of ['email', 'phone', 'company', 'address'] as const) {
			if (contact[key].required && !contact[key].shown) {
				ctx.addIssue({
					code: 'custom',
					path: [key, 'required'],
					message: 'A hidden field cannot be required. Show it first.'
				});
			}
		}
	});

export const questionSchema = z
	.object({
		id: z.string().uuid(),
		type: z.enum(FORM_QUESTION_TYPES),
		label: z.string().trim().min(1, 'A question needs some words.').max(FORM_QUESTION_LABEL_MAX),
		required: z.boolean().default(false),
		help: z.string().trim().max(FORM_QUESTION_HELP_MAX).optional(),
		options: z.array(z.string().trim().min(1).max(FORM_OPTION_MAX)).max(FORM_MAX_OPTIONS).optional()
	})
	.superRefine((question, ctx) => {
		const choices = question.options ?? [];
		const isChoice = isChoiceQuestion(question.type as FormQuestionType);
		if (isChoice && choices.length === 0) {
			ctx.addIssue({
				code: 'custom',
				path: ['options'],
				message: 'A choice question needs at least one option.'
			});
		}
		if (!isChoice && choices.length > 0) {
			ctx.addIssue({
				code: 'custom',
				path: ['options'],
				message: 'Only a dropdown, radio, or checkbox question can have options.'
			});
		}
		// Two identical options are a data-entry mistake, not a real choice.
		if (new Set(choices.map((c) => c.toLowerCase())).size !== choices.length) {
			ctx.addIssue({ code: 'custom', path: ['options'], message: 'Options must be different.' });
		}
	});

const sectionSchema = z.object({
	id: z.string().uuid(),
	title: z.string().trim().min(1, 'A section needs a title.').max(FORM_SECTION_TITLE_MAX),
	questions: z.array(questionSchema).max(FORM_MAX_QUESTIONS)
});

const confirmationSchema = z.object({
	title: z.string().trim().min(1, 'Add a confirmation title.').max(FORM_CONFIRMATION_TITLE_MAX),
	message: z
		.string()
		.trim()
		.min(1, 'Add a confirmation message.')
		.max(FORM_CONFIRMATION_MESSAGE_MAX),
	redirect_url: z
		.string()
		.trim()
		.max(FORM_REDIRECT_URL_MAX)
		.url('Enter a valid link starting with https://')
		.refine((u) => /^https?:\/\//i.test(u), 'The link must start with http:// or https://')
		.nullable()
});

export const formContentSchema = z
	.object({
		contact: contactBlockSchema,
		sections: z.array(sectionSchema).max(FORM_MAX_SECTIONS),
		photos: z.object({
			enabled: z.boolean(),
			max: z.number().int().min(1).max(FORM_MAX_PHOTOS)
		}),
		confirmation: confirmationSchema
	})
	.superRefine((content, ctx) => {
		const questions = content.sections.flatMap((s) => s.questions);
		if (questions.length > FORM_MAX_QUESTIONS) {
			ctx.addIssue({
				code: 'custom',
				path: ['sections'],
				message: `A form can have at most ${FORM_MAX_QUESTIONS} questions.`
			});
		}
		// Ids must be unique so a submitted answer maps back to exactly one question/section.
		const questionIds = questions.map((q) => q.id);
		if (new Set(questionIds).size !== questionIds.length) {
			ctx.addIssue({ code: 'custom', path: ['sections'], message: 'Question ids must be unique.' });
		}
		const sectionIds = content.sections.map((s) => s.id);
		if (new Set(sectionIds).size !== sectionIds.length) {
			ctx.addIssue({ code: 'custom', path: ['sections'], message: 'Section ids must be unique.' });
		}
	});

// Payloads ------------------------------------------------------------------------------------------------

const optionalDescription = z
	.string()
	.trim()
	.max(FORM_DESCRIPTION_MAX)
	.optional()
	.or(z.literal(''));

export const formCreateSchema = z.object({
	outcome: z.enum(FORM_OUTCOMES),
	name: z.string().trim().min(1, 'Give this form a name.').max(FORM_NAME_MAX),
	title: z.string().trim().min(1, 'Give this form a title customers will see.').max(FORM_TITLE_MAX),
	description: optionalDescription
});

export const formDraftSaveSchema = z.object({
	expected_revision: z.number().int().min(1),
	title: z.string().trim().min(1, 'Give this form a title customers will see.').max(FORM_TITLE_MAX),
	description: optionalDescription,
	content: formContentSchema
});

// Lifecycle actions on a form, chosen by `action`. `expected_revision` guards the optimistic edit: on
// publish it is the draft's revision, everywhere else the form's.
export const formActionSchema = z.discriminatedUnion('action', [
	z.object({ action: z.literal('publish'), expected_revision: z.number().int().min(1) }),
	z.object({ action: z.literal('revise') }),
	z.object({ action: z.literal('set_default'), expected_revision: z.number().int().min(1) }),
	z.object({ action: z.literal('archive'), expected_revision: z.number().int().min(1) }),
	z.object({ action: z.literal('restore'), expected_revision: z.number().int().min(1) }),
	z.object({
		action: z.literal('identity'),
		expected_revision: z.number().int().min(1),
		name: z.string().trim().min(1, 'Give this form a name.').max(FORM_NAME_MAX),
		is_enabled: z.boolean()
	})
]);

// Booking rules — Part 4B-2c. Mirrors `update_form_booking_settings`'s own checks exactly (mirrored, not
// delegated: the database remains the real boundary per CLAUDE.md rule 12; this only spares the round-trip
// for the ordinary case and gives a plain-English message).
export const formBookingSettingsSchema = z.object({
	expected_revision: z.number().int().min(1),
	requires_booking_approval: z.boolean(),
	service_area_enabled: z.boolean(),
	min_notice_minutes: z.number().int().min(0).max(BOOKING_MIN_NOTICE_MAX_MINUTES),
	slot_interval_minutes: z
		.number()
		.int()
		.min(BOOKING_SLOT_INTERVAL_MIN_MINUTES)
		.max(BOOKING_SLOT_INTERVAL_MAX_MINUTES),
	visit_duration_minutes: z
		.number()
		.int()
		.min(BOOKING_VISIT_DURATION_MIN_MINUTES)
		.max(BOOKING_VISIT_DURATION_MAX_MINUTES),
	arrival_window_minutes: z
		.number()
		.int()
		.min(0)
		.max(BOOKING_ARRIVAL_WINDOW_MAX_MINUTES)
		.nullable(),
	buffer_minutes: z.number().int().min(0).max(BOOKING_BUFFER_MAX_MINUTES),
	service_ids: z.array(z.string().uuid()).max(BOOKING_MAX_SERVICES)
});

export type FormBookingSettingsInput = z.infer<typeof formBookingSettingsSchema>;

// The sample-slots preview. Bounded the same way the database function itself is (max_range_days = 60);
// the route also caps the window it will actually ask for so the preview stays a quick card, not a report.
export const BOOKING_PREVIEW_MAX_DAYS = 14;

export const formBookingSlotsQuerySchema = z.object({
	range_start: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Give a valid start date.'),
	range_end: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Give a valid end date.')
});
