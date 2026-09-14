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
