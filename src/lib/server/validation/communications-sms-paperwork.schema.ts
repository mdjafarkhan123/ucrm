import { z } from 'zod';

// Number paperwork (Stage 10 Part 3). The answers are keyed by Twilio's own field names, which come live from
// its Regulations, so the shape is checked here and each value is checked against the country's rules when
// the set is sent (paperworkProblems in $lib/communications/number-paperwork).

const name = z.string().regex(/^[a-z][a-z0-9_]{0,63}$/);
const value = z.string().trim().max(500, 'Keep this under 500 characters.');
const values = z
	.record(name, value)
	.refine((record) => Object.keys(record).length <= 40, 'Too many answers.');

const countryCode = z
	.string()
	.trim()
	.transform((code) => code.toUpperCase())
	.refine((code) => /^[A-Z]{2}$/.test(code), 'Choose a country.');
const numberType = z.enum(['local', 'mobile', 'national', 'toll_free'], {
	message: 'Choose a kind of number.'
});
const endUserType = z.enum(['business', 'individual'], {
	message: 'Choose who will own the numbers.'
});
const revision = z.number().int().min(1);

const addressPart = (max: number) =>
	z.string().trim().max(max, `Keep this under ${max} characters.`);

export const paperworkAddressSchema = z.object({
	customer_name: addressPart(200),
	street: addressPart(200),
	street_secondary: addressPart(200),
	city: addressPart(120),
	region: addressPart(120),
	postal_code: addressPart(32),
	country_code: z
		.string()
		.trim()
		.transform((code) => code.toUpperCase())
		.refine((code) => code === '' || /^[A-Z]{2}$/.test(code), 'Choose a country.')
});

export const paperworkStartSchema = z.object({
	country_code: countryCode,
	number_type: numberType,
	end_user_type: endUserType.default('business')
});

export const paperworkSaveSchema = z.object({
	expected_revision: revision,
	end_user_type: endUserType.optional(),
	answers: values.optional(),
	address: paperworkAddressSchema.nullable().optional(),
	document_choices: z
		.record(name, name)
		.refine((record) => Object.keys(record).length <= 30, 'Too many documents.')
		.optional(),
	documents: z
		.array(z.object({ document_type: name, fields: values }))
		.max(20, 'Too many documents.')
		.optional()
});

export const paperworkSendSchema = z.object({ expected_revision: revision });

export const paperworkUploadSchema = z.object({
	document_type: name,
	file_name: z.string().trim().min(1).max(255),
	mime_type: z.string().trim().max(127),
	size_bytes: z.number().int().positive()
});

export function paperworkFieldErrors(error: z.ZodError) {
	return z.flattenError(error).fieldErrors;
}
