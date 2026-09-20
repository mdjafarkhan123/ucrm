import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { verifyTurnstileToken } from '$lib/server/security/turnstile';
import { resolvePublicForm } from '$lib/server/forms/public-resolver';
import { isBookingOutcome } from '$lib/forms/types';
import {
	buildPublicFormAnswersSchema,
	buildPublicFormContactSchema,
	publicFormEnvelopeSchema
} from '$lib/server/validation/public-forms.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import type { Json } from '$lib/database.types';
import { parsePhoneNumberFromString, type CountryCode } from 'libphonenumber-js';
import { serviceSmsConsentDisclosure } from '$lib/forms/sms-consent';
import { emailMarketingConsentDisclosure } from '$lib/forms/marketing-consent';

const NOT_AVAILABLE = { error: 'That form is not available.' };

// Postgres codes raised by submit_form_response when the submission's own shape or state is refused
// (bad idempotency key, wrong booking-field pairing, a photo key outside this form's prefix, oversized
// jsonb, too many photos, an unlisted catalog item) -- all shown as one generic sentence, since none of
// these are the visitor's business to diagnose further than "try again."
const REFUSED_CODES = new Set(['23514', '23503']);

export const POST: RequestHandler = async (event) => {
	const client = getOwnerSupabaseClient();
	const clientAddress = event.getClientAddress();
	const { orgSlug, formSlug } = event.params;

	const resolved = await resolvePublicForm(client, orgSlug, formSlug);
	if (!resolved) return json(NOT_AVAILABLE, { status: 404 });

	const rateLimit = await checkRateLimit(client, {
		bucketKey: `public-form-submit:${resolved.formId}:${clientAddress}`,
		windowSeconds: 900,
		maxAttempts: 10
	});
	if (!rateLimit.allowed) return rateLimitedResponse(rateLimit.retryAfterSeconds);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'That submission could not be read.' }, { status: 400 });
	}

	const parsedEnvelope = publicFormEnvelopeSchema.safeParse(body);
	if (!parsedEnvelope.success)
		return json(
			{
				error: 'Please review the highlighted fields.',
				field_errors: zodFieldErrors(parsedEnvelope.error)
			},
			{ status: 422 }
		);
	const envelope = parsedEnvelope.data;

	const turnstileOk = await verifyTurnstileToken(envelope.turnstile_token, clientAddress);
	if (!turnstileOk)
		return json({ error: "We couldn't verify you're human. Please try again." }, { status: 422 });

	const contactSchema = buildPublicFormContactSchema(resolved.content.contact);
	const parsedContact = contactSchema.safeParse(envelope.contact);
	if (!parsedContact.success)
		return json(
			{
				error: 'Please review the highlighted fields.',
				field_errors: zodFieldErrors(parsedContact.error)
			},
			{ status: 422 }
		);

	// Service-SMS consent (Part 4 Stage 5). Only meaningful when a phone number was entered. A ticked box needs a
	// number a text can actually reach, so a local number is read in the business's country and stored as E.164;
	// the stored evidence is the exact wording the page showed, never text sent by the browser.
	const contact: Record<string, unknown> = { ...parsedContact.data };
	const {
		sms_service_consent: smsConsentGiven,
		email_marketing_consent: emailMarketingConsentGiven,
		...restContact
	} = contact;
	const enteredPhone = typeof restContact.phone === 'string' ? restContact.phone.trim() : '';
	const submittedContact: Record<string, unknown> = restContact;

	// Marketing-email consent (Marketing M1). Only meaningful when this form asks for it and an email was entered.
	// The browser sends only yes/no; the server builds the exact disclosure from the business name shown, so the
	// stored evidence is what the visitor saw. The consent ledger records only opt-ins (see the after-processed
	// trigger private.record_form_submission_marketing_consent).
	const enteredEmail = typeof restContact.email === 'string' ? restContact.email.trim() : '';
	if (
		resolved.content.contact.email.shown &&
		resolved.content.contact.email.marketing_consent &&
		enteredEmail
	) {
		submittedContact.email_marketing_consent = {
			given: emailMarketingConsentGiven === true,
			disclosure: emailMarketingConsentDisclosure(resolved.organizationName)
		};
	}
	if (resolved.content.contact.phone.shown && enteredPhone) {
		const given = smsConsentGiven === true;
		if (given) {
			const parsed = parsePhoneNumberFromString(
				enteredPhone,
				(resolved.countryCode ?? undefined) as CountryCode | undefined
			);
			if (!parsed?.isValid())
				return json(
					{
						error: 'To get texts, enter a full mobile number, including the country code.',
						field_errors: { phone: 'Enter a full mobile number.' }
					},
					{ status: 422 }
				);
			submittedContact.phone = parsed.number;
		}
		submittedContact.sms_service_consent = {
			given,
			disclosure: serviceSmsConsentDisclosure(resolved.organizationName)
		};
	}

	const answersSchema = buildPublicFormAnswersSchema(resolved.content.sections);
	const parsedAnswers = answersSchema.safeParse(envelope.answers);
	if (!parsedAnswers.success)
		return json(
			{
				error: 'Please review the highlighted fields.',
				field_errors: zodFieldErrors(parsedAnswers.error)
			},
			{ status: 422 }
		);

	const booking = isBookingOutcome(resolved.outcome);
	if (
		!booking &&
		(envelope.selected_catalog_item_id ||
			envelope.requested_starts_at ||
			envelope.requested_ends_at)
	) {
		return json({ error: 'This form does not book a time.' }, { status: 422 });
	}
	if (booking && (!envelope.requested_starts_at || !envelope.requested_ends_at)) {
		return json({ error: 'Choose a time for this visit.' }, { status: 422 });
	}

	const maxPhotos = resolved.content.photos.enabled ? resolved.content.photos.max : 0;
	if (envelope.photo_object_keys.length > maxPhotos) {
		return json({ error: 'Too many photos on this submission.' }, { status: 422 });
	}

	const { data, error } = await client.rpc('submit_form_response', {
		target_organization_slug: resolved.organizationSlug,
		target_form_slug: formSlug,
		target_idempotency_key: envelope.idempotency_key,
		target_contact: submittedContact as Json,
		target_answers: parsedAnswers.data as Json,
		target_photo_object_keys: envelope.photo_object_keys,
		target_selected_catalog_item_id:
			(booking ? envelope.selected_catalog_item_id : null) ?? undefined,
		target_requested_starts_at: (booking ? envelope.requested_starts_at : null) ?? undefined,
		target_requested_ends_at: (booking ? envelope.requested_ends_at : null) ?? undefined
	});

	if (error) {
		if (REFUSED_CODES.has(error.code ?? '')) {
			return json(
				{ error: error.message || 'That submission could not be saved.' },
				{ status: 422 }
			);
		}
		console.error('Could not save a public form submission.', error);
		return json(
			{ error: 'We could not save your submission. Please try again shortly.' },
			{ status: 500 }
		);
	}

	return json(data, { status: 201 });
};
