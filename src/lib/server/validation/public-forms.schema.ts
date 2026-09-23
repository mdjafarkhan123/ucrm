import { z } from 'zod';
import {
	FORM_MAX_OPTIONS,
	FORM_MAX_PHOTOS,
	type ContactBlock,
	type FormContent,
	type FormQuestion
} from '$lib/forms/types';
import { PUBLIC_FORM_PHOTO_MAX_COUNT } from '$lib/server/forms/public-submission-photo';

// The public submission's shape, validated in two steps -- an envelope every form shares, then a
// per-form answer schema built from the published `FormContent` (CLAUDE.md rule 12). The database's
// `submit_form_response` re-checks the load-bearing facts itself (published/enabled/active, photo key
// prefix, gross json size, booking-field pairing) because an anonymous caller's own claims are never
// trusted twice; this layer exists for a friendly, field-level message before that round-trip.

export const publicFormEnvelopeSchema = z.object({
	turnstile_token: z.string().min(1, "Please complete the 'I am human' check."),
	idempotency_key: z.string().trim().min(1).max(200),
	contact: z.record(z.string(), z.unknown()).default({}),
	answers: z.record(z.string(), z.unknown()).default({}),
	photo_object_keys: z.array(z.string().trim().min(1)).max(PUBLIC_FORM_PHOTO_MAX_COUNT).default([]),
	selected_catalog_item_id: z.string().uuid().nullable().optional(),
	requested_starts_at: z.iso.datetime({ offset: true }).nullable().optional(),
	requested_ends_at: z.iso.datetime({ offset: true }).nullable().optional(),
	// The Marketing call-to-action token (M5b), read from the page's own `?mc=` query param. An invalid or
	// garbled value hashes to null (see marketingCtaTokenHash) and is silently ignored, never surfaced as a
	// field error -- a broken token is not the visitor's business to diagnose.
	marketing_cta_token: z.string().trim().max(200).nullable().optional()
});

export type PublicFormEnvelope = z.infer<typeof publicFormEnvelopeSchema>;

function contactFieldSchema(
	shown: boolean,
	required: boolean,
	max: number,
	kind: 'text' | 'email' = 'text'
) {
	if (!shown) return z.unknown().optional();
	const base =
		kind === 'email'
			? z.string().trim().email('Enter a valid email address.').max(max)
			: z.string().trim().max(max);
	return required ? base.min(1, 'This field is required.') : base.optional().or(z.literal(''));
}

// Same field lengths as the property address block (`propertyAddressSchema` in foundation.schema.ts) --
// this becomes that same property record once the worker runs. Only line1/city carry the block's own
// "required" flag; state/postal stay optional even on a required address, matching Property itself.
function contactAddressSchema(shown: boolean, required: boolean) {
	if (!shown) return z.unknown().optional();
	const line1 = z.string().trim().max(160);
	const city = z.string().trim().max(80);
	return z.object({
		line1: required
			? line1.min(1, 'Enter your street address.')
			: line1.optional().or(z.literal('')),
		city: required ? city.min(1, 'Enter your city.') : city.optional().or(z.literal('')),
		state_region: z.string().trim().max(80).optional().or(z.literal('')),
		postal_code: z.string().trim().max(20).optional().or(z.literal(''))
	});
}

// Mirrors exactly which contact fields the published form shows/requires -- a field the form never shows
// is never demanded, and a field the form requires cannot be skipped.
export function buildPublicFormContactSchema(contact: ContactBlock) {
	return z.object({
		name: z.string().trim().min(1, 'Enter your name.').max(200),
		email: contactFieldSchema(contact.email.shown, contact.email.required, 254, 'email'),
		phone: contactFieldSchema(contact.phone.shown, contact.phone.required, 40),
		company: contactFieldSchema(contact.company.shown, contact.company.required, 200),
		address: contactAddressSchema(contact.address.shown, contact.address.required),
		email_marketing_consent: z.boolean().optional(),
		phone_marketing_consent: z.boolean().optional(),
		// Part 4 Stage 5: the visitor ticked the service-SMS box. The submit route replaces it with the stored
		// evidence ({ given, disclosure }) after checking the number.
		sms_service_consent: z.boolean().optional()
	});
}

const ANSWER_SHORT_TEXT_MAX = 2000;
const ANSWER_LONG_TEXT_MAX = 5000;

function questionAnswerSchema(question: FormQuestion): z.ZodTypeAny {
	const options = question.options ?? [];
	let base: z.ZodTypeAny;

	switch (question.type) {
		case 'short_text':
			base = z.string().trim().max(ANSWER_SHORT_TEXT_MAX);
			break;
		case 'long_text':
			base = z.string().trim().max(ANSWER_LONG_TEXT_MAX);
			break;
		case 'number':
			base = z
				.union([
					z.number(),
					z
						.string()
						.trim()
						.regex(/^-?\d+(\.\d+)?$/, 'Enter a number.')
				])
				.transform((value) => Number(value));
			break;
		case 'yes_no':
			base = z.boolean();
			break;
		case 'dropdown':
		case 'radio':
			base = z
				.string()
				.refine((value) => options.includes(value), 'Choose one of the listed options.');
			break;
		case 'dropdown_multi':
		case 'checkbox':
			base = z
				.array(
					z.string().refine((value) => options.includes(value), 'Choose one of the listed options.')
				)
				.max(Math.max(options.length, FORM_MAX_OPTIONS));
			break;
		case 'image_upload':
			base = z.array(z.string().trim().min(1)).max(FORM_MAX_PHOTOS);
			break;
		default:
			base = z.unknown();
	}

	if (!question.required) return base.optional();

	if (
		question.type === 'dropdown_multi' ||
		question.type === 'checkbox' ||
		question.type === 'image_upload'
	) {
		return (base as z.ZodArray<z.ZodTypeAny>).min(1, 'This question is required.');
	}
	if (question.type === 'short_text' || question.type === 'long_text') {
		return (base as z.ZodString).min(1, 'This question is required.');
	}
	return base;
}

// One schema per published form, keyed by each question's stable id -- the same id the builder assigns and
// the same id a submitted answer maps back to (see $lib/forms/types.ts).
export function buildPublicFormAnswersSchema(sections: FormContent['sections']) {
	const shape: Record<string, z.ZodTypeAny> = {};
	for (const section of sections) {
		for (const question of section.questions) {
			shape[question.id] = questionAnswerSchema(question);
		}
	}
	return z.object(shape);
}
