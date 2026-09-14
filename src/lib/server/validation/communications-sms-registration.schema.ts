import { z } from 'zod';

const shortText = (label: string, max = 160) =>
	z.string().trim().min(1, `Enter ${label}.`).max(max, `Keep ${label} under ${max} characters.`);
const optionalText = (max = 160) =>
	z
		.string()
		.trim()
		.max(max, `Keep this under ${max} characters.`)
		.optional()
		.transform((value) => value || undefined);
const webUrl = z
	.string()
	.trim()
	.url('Enter a complete web address, including https://.')
	.max(2048)
	.refine((value) => value.startsWith('https://') || value.startsWith('http://'), {
		message: 'Enter a web address beginning with https:// or http://.'
	});

const addressSchema = z.object({
	line1: shortText('the street address'),
	line2: optionalText(),
	city: shortText('the city'),
	region: shortText('the state, province, or region'),
	postal_code: shortText('the postal code', 32),
	country_code: z
		.string()
		.trim()
		.transform((value) => value.toUpperCase())
		.refine((value) => /^[A-Z]{2}$/.test(value), 'Choose a country.')
});

const representativeSchema = z.object({
	first_name: shortText('the representative first name', 100),
	last_name: shortText('the representative last name', 100),
	business_title: shortText('the representative business title', 100),
	job_position: shortText('the representative job position', 100),
	email: z.string().trim().email('Enter a valid representative email.').max(320),
	phone_number: z
		.string()
		.trim()
		.regex(/^\+[1-9]\d{7,14}$/, 'Enter the representative phone in international format.')
});

const messagingSchema = z.object({
	description: shortText('how the business will use texting', 2000),
	consent_method: z.enum(['website_form', 'paper_form', 'verbal', 'text_initiated', 'other'], {
		message: 'Choose how customers agree to receive texts.'
	}),
	consent_description: shortText('how customer consent is collected', 2000),
	sample_messages: z
		.array(shortText('each sample message', 1600))
		.min(2, 'Add at least two sample messages.')
		.max(5, 'Add no more than five sample messages.'),
	privacy_policy_url: webUrl.optional(),
	terms_url: webUrl.optional(),
	estimated_monthly_messages: z.enum(['under_500', '500_2000', '2001_10000', 'over_10000'])
});

export const smsRegistrationAnswersSchema = z.object({
	legal_business_name: shortText('the legal business name', 200),
	business_type: z.enum([
		'sole_proprietorship',
		'partnership',
		'limited_liability_company',
		'cooperative',
		'nonprofit_corporation',
		'corporation',
		'other'
	]),
	business_registration_id_type: shortText('the registration ID type', 40),
	business_registration_id: shortText('the business registration ID', 100),
	website_url: webUrl,
	business_address: addressSchema,
	authorized_representative: representativeSchema,
	messaging: messagingSchema
});

const draftAnswersSchema = z.object({
	legal_business_name: optionalText(200),
	business_type: smsRegistrationAnswersSchema.shape.business_type.optional(),
	business_registration_id_type: optionalText(40),
	business_registration_id: optionalText(100),
	website_url: webUrl.optional(),
	business_address: addressSchema.partial().optional(),
	authorized_representative: representativeSchema.partial().optional(),
	messaging: messagingSchema.partial().optional()
});

const commandBase = z.object({
	expected_revision: z.number().int().min(1),
	questionnaire_version: z.literal(1)
});

export const smsRegistrationDraftSaveSchema = commandBase.extend({ answers: draftAnswersSchema });
export const smsRegistrationSubmitSchema = commandBase.extend({
	answers: smsRegistrationAnswersSchema,
	confirm_authorized_representative: z.literal(true, {
		message: 'Confirm that you are authorized to represent this business.'
	})
});

export function smsRegistrationFieldErrors(error: z.ZodError) {
	return z.flattenError(error).fieldErrors;
}

export type SmsRegistrationAnswers = z.infer<typeof smsRegistrationAnswersSchema>;
