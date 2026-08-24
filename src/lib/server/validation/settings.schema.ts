import { z } from 'zod';

// Business Profile, Branding, and Business Hours are three pages that save on their own. Each sends only
// its own fields and its own revision, so a tab left open on one of them cannot undo another's save.
// An empty box means "cleared", so blanks become null here rather than reaching the database as ''.
const optionalText = (max: number, message?: string) =>
	z
		.string()
		.trim()
		.max(max, message ?? `Keep this under ${max} characters.`)
		.nullish()
		.transform((value) => value || null);

const expectedRevision = z.number().int().min(1);

const TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/;

export const businessProfileSchema = z.object({
	expected_revision: expectedRevision,
	name: z.string().trim().min(2, 'Enter your business name.').max(120),
	trade: optionalText(120),
	phone: optionalText(32),
	website: optionalText(2048),
	description: optionalText(500, 'Keep the description under 500 characters.'),
	address_line1: optionalText(160),
	address_line2: optionalText(160),
	city: optionalText(120),
	region: optionalText(120),
	postal_code: optionalText(20),
	// The country combobox saves the ISO code, never the typed name.
	country_code: z
		.string()
		.trim()
		.nullish()
		.transform((value) => (value ? value.toUpperCase() : null))
		.refine((value) => value === null || /^[A-Z]{2}$/.test(value), {
			message: 'Choose a country from the list.'
		}),
	// Off keeps the street off customer documents; they still see the city and state.
	address_is_public: z.boolean().default(false),
	// Guidance only. The database checks this against pg_timezone_names, which is the real boundary.
	timezone: z.string().trim().min(1, 'Choose a timezone.').max(80),
	currency_code: z
		.string()
		.trim()
		.transform((value) => value.toUpperCase())
		.refine((value) => /^[A-Z]{3}$/.test(value), { message: 'Choose a currency.' }),
	// The browser's timezone and the country's currency are suggestions the page shows. These say the
	// person actually chose the value; without them the database refuses to change either one.
	confirm_timezone: z.boolean().default(false),
	confirm_currency: z.boolean().default(false)
});

export type BusinessProfileInput = z.infer<typeof businessProfileSchema>;

// One period of one day. A closed day and an all-day day carry no times at all; a real period carries
// both, and a closing time earlier than the opening time is how a period runs past midnight.
export const businessHourPeriodSchema = z
	.object({
		weekday: z.number().int().min(0).max(6),
		period_index: z.number().int().min(0).max(2),
		is_open: z.boolean(),
		is_open_24h: z.boolean().default(false),
		opens_at: z
			.string()
			.regex(TIME_PATTERN, 'Enter an opening time.')
			.nullish()
			.transform((value) => value || null),
		closes_at: z
			.string()
			.regex(TIME_PATTERN, 'Enter a closing time.')
			.nullish()
			.transform((value) => value || null)
	})
	.refine((value) => !(value.is_open_24h && !value.is_open), {
		path: ['is_open_24h'],
		message: 'Mark the day open before setting it to 24 hours.'
	})
	.refine((value) => !(value.is_open_24h && (value.opens_at || value.closes_at)), {
		path: ['is_open_24h'],
		message: 'A day open 24 hours does not need opening and closing times.'
	})
	.refine((value) => !(!value.is_open && (value.opens_at || value.closes_at)), {
		path: ['opens_at'],
		message: 'A closed day cannot have opening and closing times.'
	})
	.refine(
		(value) =>
			!value.is_open ||
			value.is_open_24h ||
			(value.opens_at !== null && value.closes_at !== null && value.opens_at !== value.closes_at),
		{
			path: ['opens_at'],
			message: 'Set an opening and a closing time, or mark the day closed.'
		}
	);

export const businessHoursSchema = z
	.object({
		expected_revision: expectedRevision,
		// 'not_configured' is where an organization starts, not something anyone saves.
		mode: z.enum(['weekly', 'appointment_only'], 'Choose weekly hours or appointment only.'),
		periods: z.array(businessHourPeriodSchema).max(21).default([])
	})
	.refine(
		(value) =>
			value.mode !== 'weekly' || new Set(value.periods.map((period) => period.weekday)).size === 7,
		{ path: ['periods'], message: 'Business hours need every day of the week.' }
	);

export type BusinessHoursInput = z.infer<typeof businessHoursSchema>;

export const brandingSchema = z.object({
	expected_revision: expectedRevision,
	brand_color: z
		.string()
		.trim()
		.nullish()
		.transform((value) => value || null)
		.refine((value) => value === null || /^#[0-9A-Fa-f]{6}$/.test(value), {
			message: 'Pick a brand color.'
		})
});

export type BrandingInput = z.infer<typeof brandingSchema>;

// The Pipeline board's one presentation choice: whether Assessment shows as a single column or as its
// three protected stages. It changes nothing about how work moves — only how many columns a contractor
// looks at — so a boolean is the whole shape.
export const pipelinePresentationSchema = z.object({
	expected_revision: expectedRevision,
	detailed_assessment_stages: z.boolean()
});

export type PipelinePresentationInput = z.infer<typeof pipelinePresentationSchema>;

// A saved rate's own two fields. 100 basis points is 1%, so an integer already carries up to two decimal
// places of percentage — the same bound `organization_tax_rates` checks.
const taxRateName = z
	.string()
	.trim()
	.min(1, 'Give this tax rate a name.')
	.max(80, 'Keep the name under 80 characters.');
const taxRateBasisPoints = z
	.number()
	.int('Enter the rate in basis points.')
	.gt(0, 'A tax rate is greater than 0%.')
	.max(10000, 'A tax rate cannot be more than 100%.');

export const taxRateCreateSchema = z.object({
	name: taxRateName,
	rate_basis_points: taxRateBasisPoints
});

export type TaxRateCreateInput = z.infer<typeof taxRateCreateSchema>;

export const taxRateUpdateSchema = z.object({
	expected_revision: expectedRevision,
	name: taxRateName,
	rate_basis_points: taxRateBasisPoints
});

export type TaxRateUpdateInput = z.infer<typeof taxRateUpdateSchema>;

export const taxRateActiveSchema = z.object({
	expected_revision: expectedRevision,
	is_active: z.boolean()
});

export type TaxRateActiveInput = z.infer<typeof taxRateActiveSchema>;

export const taxRateDeleteSchema = z.object({
	expected_revision: expectedRevision
});

export type TaxRateDeleteInput = z.infer<typeof taxRateDeleteSchema>;

// The Business default is one saved active rate or the explicit No tax choice — never "not configured",
// which is only where an organization starts, not something anyone saves back to.
export const taxDefaultSchema = z
	.object({
		expected_revision: expectedRevision,
		source: z.enum(['rate', 'no_tax'], { message: 'Choose a saved rate or No tax.' }),
		rate_id: z
			.string()
			.uuid()
			.nullish()
			.transform((value) => value ?? null)
	})
	.refine((value) => value.source !== 'rate' || value.rate_id !== null, {
		path: ['rate_id'],
		message: 'Choose a saved tax rate.'
	});

export type TaxDefaultInput = z.infer<typeof taxDefaultSchema>;

// Serving an uploaded image inline from our own origin is how a file becomes a way to run code on the
// app's domain, so the logo is limited to formats a browser renders as a picture and nothing else.
// SVG is deliberately absent: it is a document that can carry script.
export const LOGO_MIME_TYPES = ['image/png', 'image/jpeg', 'image/webp'] as const;
export const LOGO_MAX_BYTES = 2 * 1024 * 1024;

export const logoUploadSchema = z.object({
	file_name: z.string().trim().min(1, 'Choose a file.').max(200),
	mime_type: z.enum(LOGO_MIME_TYPES, 'Upload a PNG, JPG, or WEBP image.'),
	size_bytes: z
		.number()
		.int()
		.positive('That file is empty.')
		.max(LOGO_MAX_BYTES, 'Logos have to be under 2 MB.')
});

export const logoCommitSchema = z.object({
	object_key: z.string().trim().min(1).max(512)
});

// Quote Settings, Part 2C. Terms arrives as raw safe-formatting HTML; the route sanitizes it to the
// approved allow-list before this length cap matters and before the database ever sees it. The generous raw
// ceiling here only stops an absurd payload from reaching the sanitizer at all.
export const quoteTermsSchema = z.object({
	expected_revision: expectedRevision,
	terms: z
		.string()
		.max(50000, 'That is too much text.')
		.nullish()
		.transform((value) => value ?? '')
});

export type QuoteTermsInput = z.infer<typeof quoteTermsSchema>;

// Enabling requires a name; title and a signature (uploaded object key, or a drawn data URL decoded by the
// route) are optional and mutually exclusive as inputs -- only one signature source is ever the request's.
// The signature's storage key is never sent to the browser (see the route's own comment on why), so a save
// that touches only name/title/enabled has no way to resend the current one -- `remove_signature` is the
// explicit third state, and omitting all three means "leave whatever is saved alone," which the route
// resolves by re-reading the current key rather than the browser guessing at it.
export const quoteRepresentativeSchema = z
	.object({
		expected_revision: expectedRevision,
		enabled: z.boolean(),
		name: optionalText(160, 'Keep the representative name under 160 characters.'),
		title: optionalText(160, 'Keep the title under 160 characters.'),
		signature_object_key: z
			.string()
			.trim()
			.min(1)
			.max(512)
			.nullish()
			.transform((value) => value || null),
		signature_image: z
			.string()
			.trim()
			.min(1)
			.nullish()
			.transform((value) => value || null),
		remove_signature: z.boolean().default(false)
	})
	.refine((value) => !value.enabled || value.name !== null, {
		path: ['name'],
		message: 'Enter a representative name.'
	})
	.refine(
		(value) =>
			[
				value.signature_object_key !== null,
				value.signature_image !== null,
				value.remove_signature
			].filter(Boolean).length <= 1,
		{
			path: ['signature_image'],
			message: 'Choose an uploaded signature, a drawn one, or removal -- not more than one.'
		}
	);

export type QuoteRepresentativeInput = z.infer<typeof quoteRepresentativeSchema>;

// Not set (null) is the honest starting state -- the route lets a save clear it back to null.
export const quoteTargetMarginSchema = z.object({
	expected_revision: expectedRevision,
	margin_basis_points: z
		.number()
		.int()
		.gt(0, 'Target margin must be greater than 0%.')
		.lt(10000, 'Target margin must be below 100%.')
		.nullable()
});

export type QuoteTargetMarginInput = z.infer<typeof quoteTargetMarginSchema>;

export const quoteSignaturePolicySchema = z.object({
	expected_revision: expectedRevision,
	require_customer_signature: z.boolean()
});

export type QuoteSignaturePolicyInput = z.infer<typeof quoteSignaturePolicySchema>;

// A signature image is smaller than a logo, so a tighter ceiling catches an oversized upload before it
// reaches R2.
export const QUOTE_REPRESENTATIVE_SIGNATURE_MIME_TYPES = [
	'image/png',
	'image/jpeg',
	'image/webp'
] as const;
export const QUOTE_REPRESENTATIVE_SIGNATURE_MAX_BYTES = 1 * 1024 * 1024;

export const quoteRepresentativeSignatureUploadSchema = z.object({
	file_name: z.string().trim().min(1, 'Choose a file.').max(200),
	mime_type: z.enum(QUOTE_REPRESENTATIVE_SIGNATURE_MIME_TYPES, 'Upload a PNG, JPG, or WEBP image.'),
	size_bytes: z
		.number()
		.int()
		.positive('That file is empty.')
		.max(QUOTE_REPRESENTATIVE_SIGNATURE_MAX_BYTES, 'Signature images have to be under 1 MB.')
});
