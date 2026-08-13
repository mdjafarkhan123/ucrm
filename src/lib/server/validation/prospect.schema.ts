import { z } from 'zod';

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

export const prospectPackageCorrectionSchema = z.object({
	package_version_id: z.string().uuid('Choose a package.'),
	reason: z.string().trim().min(1, 'Enter a private reason for this correction.').max(500)
});

export const prospectPaymentReversalSchema = z.object({
	reason: z.string().trim().min(1, 'Enter a private reason for the reversal.').max(500)
});

export const prospectPaymentConfirmationSchema = z.object({
	amount_usd_cents: z.number().int().positive('Enter the amount received.'),
	private_reference: z
		.string()
		.trim()
		.min(1, 'Enter a private payment reference.')
		.max(240, 'Keep the payment reference under 240 characters.'),
	mismatch_reason: z
		.string()
		.trim()
		.min(1, 'Enter a reason for the amount mismatch.')
		.max(500, 'Keep the mismatch reason under 500 characters.')
		.nullish()
});
