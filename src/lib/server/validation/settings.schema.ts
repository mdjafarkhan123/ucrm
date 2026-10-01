import { z } from 'zod';
import {
	BOARD_SECTIONS,
	BOARD_SECTION_LABELS,
	BOARD_STAGES,
	CUSTOM_STAGE_LIMIT,
	CUSTOM_STAGE_NAME_MAX,
	QUOTE_BOARD_STAGES,
	SECTION_STAGES,
	protectedNamesInSection
} from '$lib/pipeline/stages';

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

// The service-area radius (Contractor Settings Part 4B-2a/4B-2c). Saved by its own command
// (`update_organization_service_area_radius`) but guarded by the same `profile_revision` as the rest of this
// page — see 20260913160000_contractor_settings_booking_rules_foundation.sql § 5.
export const serviceAreaRadiusSchema = z.object({
	expected_revision: expectedRevision,
	radius_miles: z
		.number({ message: 'Enter a service area radius.' })
		.min(0.1, 'Radius must be at least 0.1 miles.')
		.max(500, 'Radius cannot be more than 500 miles.')
});

export type ServiceAreaRadiusInput = z.infer<typeof serviceAreaRadiusSchema>;

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

// Settings → Pipeline: the Assessment toggle and the organization's whole list of custom stages, saved
// together. The list is every enabled stage in board order; an entry without an id is a new one. The
// database repeats the limit and the same-name rule, because it is the one that sees two people saving at
// once — this copy exists to name the exact row that is wrong.
const customStageSchema = z
	.object({
		id: z.string().uuid().nullable(),
		section: z.enum(BOARD_SECTIONS),
		name: z
			.string()
			.trim()
			.min(1, 'Give this stage a name.')
			.max(CUSTOM_STAGE_NAME_MAX, `Keep the name under ${CUSTOM_STAGE_NAME_MAX} characters.`),
		after_stage: z.enum([...BOARD_STAGES, ...QUOTE_BOARD_STAGES]),
		// On hold: cards need an open Task due after today to be moved in.
		requires_future_task: z.boolean().default(false)
	})
	.refine((stage) => SECTION_STAGES[stage.section].includes(stage.after_stage), {
		message: 'That stage cannot sit there.',
		path: ['after_stage']
	});

export const pipelineSettingsSchema = z
	.object({
		expected_revision: expectedRevision,
		detailed_assessment_stages: z.boolean(),
		stages: z
			.array(customStageSchema)
			.max(CUSTOM_STAGE_LIMIT, `A pipeline can have up to ${CUSTOM_STAGE_LIMIT} custom stages.`)
	})
	.superRefine((settings, context) => {
		const taken = new Map<string, Set<string>>(
			BOARD_SECTIONS.map((section) => [
				section,
				new Set(protectedNamesInSection(section).map((name) => name.toLowerCase()))
			])
		);
		settings.stages.forEach((stage, index) => {
			const names = taken.get(stage.section);
			const name = stage.name.toLowerCase();
			if (names?.has(name)) {
				context.addIssue({
					code: 'custom',
					message: `${BOARD_SECTION_LABELS[stage.section]} already has a stage called “${stage.name}”.`,
					path: ['stages', index, 'name']
				});
			}
			names?.add(name);
		});
	});

export type PipelineSettingsInput = z.infer<typeof pipelineSettingsSchema>;

// Switching a custom stage off. `destination` is where its cards go: another custom stage's id, the word
// below for "back to each card's own built-in stage", or null when the person was never asked — which the
// database accepts only for a stage holding no cards.
export const BUILT_IN_DESTINATION = 'built_in';

export const disablePipelineStageSchema = z.object({
	expected_revision: expectedRevision,
	destination: z
		.union([z.literal(BUILT_IN_DESTINATION), z.string().uuid()], {
			message: 'Choose where these cards go.'
		})
		.nullable()
});

export type DisablePipelineStageInput = z.infer<typeof disablePipelineStageSchema>;

// Which contact decides when a website chat or form's phone and email belong to two different clients.
export const contactMatchPrioritySchema = z.object({
	expected_revision: expectedRevision,
	priority: z.enum(['email', 'phone'], { message: 'Choose email or phone.' })
});

export type ContactMatchPriorityInput = z.infer<typeof contactMatchPrioritySchema>;

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

// Invoice payment terms (Contractor Settings Part 5A). Unlike every other organization_settings counter,
// invoice_settings_revision starts at 0, not 1 — a brand new organization's very first term save legitimately
// names revision 0 — so this gets its own expected-revision bound instead of reusing `expectedRevision`.
const expectedInvoiceRevision = z.number().int().min(0);

const invoicePaymentTermName = z
	.string()
	.trim()
	.min(2, 'A payment term needs a name between 2 and 60 characters.')
	.max(60, 'A payment term needs a name between 2 and 60 characters.');

// Matches the database's own rule check (`save_invoice_payment_term`) so a bad choice never reaches it.
const invoicePaymentTermRule = z.enum(['on_receipt', 'net_days', 'month_end', 'next_month_end'], {
	message: 'Choose how this term works out its due date.'
});

export const invoicePaymentTermSaveSchema = z
	.object({
		expected_revision: expectedInvoiceRevision,
		name: invoicePaymentTermName,
		rule: invoicePaymentTermRule,
		net_days: z
			.number()
			.int('A net term needs a whole number of days.')
			.min(1, 'A net term needs a day count between 1 and 365.')
			.max(365, 'A net term needs a day count between 1 and 365.')
			.nullish()
			.transform((value) => value ?? null)
	})
	.refine((value) => value.rule !== 'net_days' || value.net_days !== null, {
		path: ['net_days'],
		message: 'Enter how many days after issue this term is due.'
	});

export type InvoicePaymentTermSaveInput = z.infer<typeof invoicePaymentTermSaveSchema>;

export const invoicePaymentTermRemoveSchema = z.object({
	expected_revision: expectedInvoiceRevision
});

export type InvoicePaymentTermRemoveInput = z.infer<typeof invoicePaymentTermRemoveSchema>;

export const invoiceDefaultsSchema = z.object({
	expected_revision: expectedInvoiceRevision,
	residential_term_id: z.string().uuid('Choose a payment term.'),
	commercial_term_id: z.string().uuid('Choose a payment term.')
});

export type InvoiceDefaultsInput = z.infer<typeof invoiceDefaultsSchema>;

// Serving an uploaded image inline from our own origin is how a file becomes a way to run code on the
// app's domain, so the logo is limited to formats a browser renders as a picture and nothing else.
// SVG is deliberately absent: it is a document that can carry script.
export const LOGO_MIME_TYPES = ['image/png', 'image/jpeg', 'image/webp'] as const;
export const LOGO_MAX_BYTES = 2 * 1024 * 1024;

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

// Settings → Payments (online payments Part 2). The key is only ever accepted here and passed straight to
// the server-side connection module; it is never echoed back or stored in plaintext.
export const stripeConnectSchema = z
	.object({
		api_key: z
			.string()
			.trim()
			.regex(/^rk_(test|live)_[A-Za-z0-9]{20,255}$/, {
				message: 'Paste a restricted key. It starts with rk_live_ (or rk_test_ for practice mode).'
			})
	})
	.strict();

// Pay-by-app handles (docs/online-payments-behavior-contract.md §6). A contractor may paste a full profile
// link or lead with @/$ -- these strip that down to the bare handle UCRM builds its own link from, so
// venmo.com/u/<handle>, cash.app/$<handle> and paypal.me/<handle> always come out right.
const optionalHandle = (opts: { max: number; strip: string[]; pattern: RegExp; message: string }) =>
	z
		.string()
		.trim()
		.nullish()
		.transform((value) => {
			if (!value) return null;
			let cleaned = value;
			for (const prefix of opts.strip) {
				if (cleaned.toLowerCase().startsWith(prefix)) cleaned = cleaned.slice(prefix.length);
			}
			return cleaned.trim() || null;
		})
		.refine((value) => value === null || (value.length <= opts.max && opts.pattern.test(value)), {
			message: opts.message
		});

const venmoUsername = optionalHandle({
	max: 30,
	strip: ['@'],
	pattern: /^[A-Za-z0-9_-]{5,30}$/,
	message: 'Enter a Venmo username: 5-30 letters, numbers, underscores or hyphens.'
});

const cashAppCashtag = optionalHandle({
	max: 20,
	strip: ['$'],
	pattern: /^[A-Za-z0-9_]{1,20}$/,
	message: 'Enter a Cash App $Cashtag: up to 20 letters, numbers or underscores.'
});

const paypalMeUsername = optionalHandle({
	max: 50,
	strip: ['https://paypal.me/', 'http://paypal.me/', 'www.paypal.me/', 'paypal.me/'],
	pattern: /^[A-Za-z0-9.]{1,50}$/,
	message: 'Enter your PayPal.me username -- the part after paypal.me/.'
});

// Zelle takes either an email or a phone number; whichever the contractor uses with their own bank.
const zelleContact = z
	.string()
	.trim()
	.nullish()
	.transform((value) => value || null)
	.refine(
		(value) =>
			value === null ||
			(value.length <= 254 &&
				(z.string().email().safeParse(value).success || /^[+()0-9][()0-9\s-]{6,19}$/.test(value))),
		{ message: 'Enter the email or phone number you use for Zelle.' }
	);

const eTransferEmail = z
	.string()
	.trim()
	.toLowerCase()
	.nullish()
	.transform((value) => value || null)
	.refine((value) => value === null || z.string().email().max(254).safeParse(value).success, {
		message: 'Enter a valid email for Interac e-Transfer.'
	});

export const paymentSettingsSchema = z
	.object({
		expected_revision: expectedRevision,
		online_invoice_payments_enabled: z.boolean(),
		online_deposit_payments_enabled: z.boolean(),
		online_tips_enabled: z.boolean(),
		online_receipt_email_enabled: z.boolean(),
		pay_by_app_venmo_username: venmoUsername,
		pay_by_app_cash_app_cashtag: cashAppCashtag,
		pay_by_app_paypal_me_username: paypalMeUsername,
		pay_by_app_zelle_contact: zelleContact,
		pay_by_app_e_transfer_email: eTransferEmail,
		pay_by_app_bank_transfer_instructions: optionalText(
			1000,
			'Keep bank transfer instructions under 1000 characters.'
		)
	})
	.strict();

export type PaymentSettingsInput = z.infer<typeof paymentSettingsSchema>;
