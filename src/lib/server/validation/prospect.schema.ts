import { z } from 'zod';
import { calendarDate } from './owner.schema';

export const prospectStageSchema = z.enum([
	'new',
	'awaiting_payment',
	'payment_confirmed',
	'needs_attention',
	'account_created',
	'not_proceeding'
]);

export const prospectIdSchema = z.string().uuid();

export const prospectListQuerySchema = z.object({
	stage: prospectStageSchema.optional(),
	search: z.string().trim().max(100).optional()
});

export const prospectCorrectionSchema = z.object({
	business_name: z.string().trim().min(1, 'Enter the business name.').max(160),
	main_contact_name: z.string().trim().min(1, 'Enter the main contact name.').max(160),
	main_contact_email: z
		.string()
		.trim()
		.toLowerCase()
		.email('Enter a valid contact email address.')
		.max(254),
	main_contact_phone: z.string().trim().min(1, 'Enter the main contact phone number.').max(40),
	initial_administrator_name: z.string().trim().min(1).max(160).nullish(),
	initial_administrator_email: z
		.string()
		.trim()
		.toLowerCase()
		.email('Enter a valid administrator email address.')
		.max(254)
		.nullish(),
	trade: z.string().trim().min(1, 'Enter the trade.').max(120),
	city_country: z.string().trim().min(1, 'Enter the city and country.').max(160),
	time_zone: z.string().trim().min(1, 'Enter the time zone.').max(64),
	note: z.string().trim().max(2000).nullish(),
	reason: z.string().trim().min(1, 'Enter a private reason for this correction.').max(500)
});

export const prospectNotProceedingSchema = z.object({
	reason: z.string().trim().min(1, 'Enter a private reason.').max(500).nullish()
});

export const prospectPaymentReversalSchema = z.object({
	reason: z.string().trim().min(1, 'Enter a private reason for the reversal.').max(500)
});

// Package builder P10: the initial payment is a receipt, recorded with the same fields as any later one.
export const prospectPaymentConfirmationSchema = z.object({
	received_on: calendarDate,
	amount_usd_cents: z.number().int().positive('Enter the amount received.'),
	method: z.string().trim().min(1, 'Enter how the money was paid.').max(80),
	private_reference: z
		.string()
		.trim()
		.min(1, 'Enter a private payment reference.')
		.max(240, 'Keep the payment reference under 240 characters.'),
	note: z.string().trim().max(1000, 'Keep the note under 1,000 characters.').nullish()
});

export const prospectPackageCorrectionSchema = z.object({
	edition_id: z.string().uuid('Choose a package.'),
	billing_interval: z.enum(['month', 'year'], { message: 'Choose monthly or yearly billing.' }),
	reason: z.string().trim().min(1, 'Enter a private reason for this change.').max(500)
});

// The covered dates Jafar reviewed; activation refuses if they no longer match.
// P11b adds the offer: honor or drop one the customer was shown that has since closed, or a code Jafar
// typed, and the first charge he reviewed.
const activationOfferFields = {
	offer_decision: z.enum(['honor', 'drop']).nullish(),
	offer_code: z
		.string()
		.trim()
		.toUpperCase()
		.max(32, 'A code is at most 32 characters.')
		.nullish()
		.transform((code) => code || null)
};

export const prospectActivationPreviewSchema = z.object(activationOfferFields);

export const prospectActivationSchema = z.object({
	covered_from: calendarDate,
	covered_through: calendarDate,
	...activationOfferFields,
	expected_first_charge_usd_cents: z.number().int().min(0).max(100_000_000).nullish()
});

// Multi-industry foundation B3: Uplift confirms the kind of business an Application is, or holds it while it
// checks a missing fact. The buyer reads the held message on their status page; the reason stays private.
export const prospectQualificationSchema = z.discriminatedUnion('outcome', [
	z.object({
		outcome: z.literal('supported'),
		experience_key: z.string().trim().min(1, 'Choose the kind of business.').max(40),
		business_type_key: z.string().trim().min(1, 'Choose the business type.').max(40),
		reviewed_work: z
			.string()
			.trim()
			.min(1, 'Describe the work you reviewed.')
			.max(1000, 'Keep this under 1,000 characters.'),
		reason: z.string().trim().min(1, 'Enter a private reason.').max(1000)
	}),
	z.object({
		outcome: z.literal('holding'),
		buyer_message: z
			.string()
			.trim()
			.min(1, 'Tell the business what you are checking.')
			.max(500, 'Keep this under 500 characters.'),
		reason: z.string().trim().min(1, 'Enter a private reason.').max(1000)
	})
]);
