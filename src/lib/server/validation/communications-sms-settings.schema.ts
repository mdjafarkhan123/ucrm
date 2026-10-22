import { z } from 'zod';

// Naming a number is local metadata only. An empty name clears the label back to the phone number, so we accept
// an empty string or null and normalise both to null; a real name is capped at 60 characters (the command's rule).
const displayName = z
	.union([z.string(), z.null()])
	.transform((value) => {
		if (value === null) return null;
		const trimmed = value.trim();
		return trimmed.length === 0 ? null : trimmed;
	})
	.refine((value) => value === null || value.length <= 60, {
		message: 'Keep the number name under 60 characters.'
	});

const renameSchema = z.object({
	action: z.literal('rename'),
	display_name: displayName
});

const setDefaultSchema = z.object({
	action: z.literal('set_default')
});

// One PATCH endpoint per number handles the two contractor-safe actions: rename it, or make it the default.
export const smsNumberActionSchema = z.discriminatedUnion('action', [
	renameSchema,
	setDefaultSchema
]);

// Compliance settings mirror HighLevel's SMS Compliance tab. A disabled toggle keeps any stored custom text; the
// interval is 1-60 days. Empty custom text falls back to the system default wording.
const complianceText = z
	.union([z.string(), z.null()])
	.transform((value) => {
		if (value === null) return null;
		const trimmed = value.trim();
		return trimmed.length === 0 ? null : trimmed;
	})
	.refine((value) => value === null || value.length <= 320, {
		message: 'Keep this wording under 320 characters.'
	});

export const smsComplianceSchema = z.object({
	opt_out_enabled: z.boolean(),
	opt_out_text: complianceText,
	sender_info_enabled: z.boolean(),
	sender_info_text: complianceText,
	periodic_reinsert_days: z
		.number()
		.int()
		.min(1, 'Choose between 1 and 60 days.')
		.max(60, 'Choose between 1 and 60 days.')
});

export function smsSettingsFieldErrors(error: z.ZodError) {
	return z.flattenError(error).fieldErrors;
}

export type SmsNumberAction = z.infer<typeof smsNumberActionSchema>;
export type SmsComplianceInput = z.infer<typeof smsComplianceSchema>;

// Stage 3D: a contractor's own SMS credit top-up request. Money creates no spendable credit until Jafar
// confirms it (communication_sms_confirm_credit_topup); this only validates the request itself, mirroring the
// owner-side cap in owner.schema.ts so the same amount is refused consistently on both sides of the request.
const offsiteReference = z
	.union([z.string(), z.null()])
	.optional()
	.transform((value) => {
		if (value === null || value === undefined) return null;
		const trimmed = value.trim();
		return trimmed.length === 0 ? null : trimmed;
	})
	.refine((value) => value === null || value.length <= 500, {
		message: 'Keep the payment reference under 500 characters.'
	});

const topupNote = z
	.union([z.string(), z.null()])
	.optional()
	.transform((value) => {
		if (value === null || value === undefined) return null;
		const trimmed = value.trim();
		return trimmed.length === 0 ? null : trimmed;
	})
	.refine((value) => value === null || value.length <= 2000, {
		message: 'Keep the note under 2,000 characters.'
	});

export const smsCreditTopupRequestSchema = z.object({
	requested_amount_minor: z
		.number()
		.int('Enter a whole amount in cents.')
		.positive('Enter an amount greater than zero.')
		.max(100_000_000, 'That amount is too large.'),
	offsite_reference: offsiteReference,
	note: topupNote
});

export type SmsCreditTopupRequestInput = z.infer<typeof smsCreditTopupRequestSchema>;

// Add number (Stage 10 Part 2). Countries are ISO codes Twilio sells numbers in; the server re-reads the chosen number
// from Twilio's live stock before buying, so the browser only names it.
const countryCode = z
	.string()
	.trim()
	.toUpperCase()
	.regex(/^[A-Z]{2}$/, 'Choose a country.');
const numberType = z.enum(['local', 'mobile', 'national', 'toll_free'], {
	message: 'Choose a kind of number.'
});
const flag = z
	.enum(['true', 'false'])
	.optional()
	.transform((value) => value === 'true');

export const smsNumberCountrySchema = countryCode;

export const smsNumberSearchSchema = z.object({
	country: countryCode,
	type: numberType,
	contains: z
		.string()
		.trim()
		.transform((value) => value.replace(/[^0-9A-Za-z*]/g, ''))
		.refine((value) => value.length === 0 || (value.length >= 2 && value.length <= 16), {
			message: 'Type 2 to 16 digits or letters.'
		})
		.optional(),
	mms: flag,
	voice: flag
});

export const smsNumberOrderSchema = z.object({
	idempotency_key: z.string().trim().min(8).max(200),
	phone_number: z
		.string()
		.trim()
		.regex(/^\+[1-9][0-9]{7,14}$/, 'Choose a number.'),
	country_code: countryCode,
	number_type: numberType
});
