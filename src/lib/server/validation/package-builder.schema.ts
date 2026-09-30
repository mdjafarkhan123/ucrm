import { z } from 'zod';

// Package builder P6: the draft commands behind Jafar's Packages page (ADR 0003 decision 3). The limits
// mirror the database checks on packages and package_editions so a bad value is explained here, not
// refused there.

export const packageIdSchema = z.string().uuid('The package identifier is invalid.');

const slugSchema = z
	.string()
	.trim()
	.toLowerCase()
	.min(2, 'Enter a web address of at least 2 characters.')
	.max(60, 'Keep the web address under 60 characters.')
	.regex(
		/^[a-z0-9]+(-[a-z0-9]+)*$/,
		'Use lowercase letters, numbers, and single dashes between words.'
	);

const nameSchema = z
	.string()
	.trim()
	.min(2, 'Enter a name of at least 2 characters.')
	.max(80, 'Keep the name under 80 characters.');

const priceSchema = z
	.number()
	.int('Enter a price in dollars and cents.')
	.min(0, 'A price cannot be negative.')
	.max(100_000_000, 'Enter a price under $1,000,000.')
	.nullable();

const capabilityKeySchema = z.string().regex(/^[a-z][a-z0-9_.-]{1,79}$/);

const allowanceSchema = z
	.object({
		key: z.string().regex(/^[a-z][a-z0-9_]{1,79}$/),
		state: z.enum(['numeric', 'unlimited', 'not_included']),
		value: z
			.number()
			.int('Enter a whole number.')
			.min(0, 'An allowance cannot be negative.')
			.max(10_000_000, 'Enter a number under 10,000,000.')
			.nullable()
	})
	.refine((allowance) => allowance.state !== 'numeric' || allowance.value !== null, {
		message: 'Enter a number.',
		path: ['value']
	})
	.transform((allowance) =>
		allowance.state === 'numeric' ? allowance : { ...allowance, value: null }
	);

export const packageDraftTermsSchema = z.object({
	slug: slugSchema,
	name: nameSchema,
	promise: z.string().trim().max(300, 'Keep the promise under 300 characters.'),
	highlights: z
		.array(
			z
				.string()
				.trim()
				.min(2, 'Enter a highlight of at least 2 characters.')
				.max(80, 'Keep each highlight under 80 characters.')
		)
		.max(12, 'Keep to 12 highlights or fewer.'),
	included_services: z
		.array(
			z.object({
				name: z
					.string()
					.trim()
					.min(2, 'Enter a service name of at least 2 characters.')
					.max(80, 'Keep the service name under 80 characters.'),
				description: z.string().trim().max(300, 'Keep the description under 300 characters.')
			})
		)
		.max(12, 'Keep to 12 services or fewer.'),
	exclusions: z.string().trim().max(2000, 'Keep this under 2,000 characters.'),
	monthly_price_usd_cents: priceSchema,
	yearly_price_usd_cents: priceSchema,
	capabilities: z.array(capabilityKeySchema).max(60),
	allowances: z.array(allowanceSchema).max(40)
});

export type PackageDraftTerms = z.infer<typeof packageDraftTermsSchema>;

export const createPackageSchema = z.object({
	slug: slugSchema,
	name: nameSchema,
	idempotency_key: z.string().uuid('Open the dialog again and try once more.'),
	copy_from_package_id: packageIdSchema.nullish()
});

const draftRevisionSchema = {
	edition_id: z.string().uuid('The draft identifier is invalid.'),
	revision: z.number().int().positive()
};

export const savePackageDraftSchema = z.object({
	...draftRevisionSchema,
	terms: packageDraftTermsSchema
});

export const deletePackageDraftSchema = z.object(draftRevisionSchema);

// Field errors keyed by their full path, so the builder can place "highlights.2" next to that highlight.
export function packageFieldErrors(error: z.ZodError) {
	return Object.fromEntries(
		error.issues.map((issue) => {
			const path = issue.path.filter((part) => part !== 'terms').join('.');
			return [path || 'form', issue.message] as const;
		})
	);
}

// Package builder P7: publishing names the exact draft and revision Jafar reviewed.
export const publishPackageDraftSchema = z.object(draftRevisionSchema);

// Package builder P7: catalog actions change the package, never an edition's terms.
export const packageCatalogActionSchema = z.discriminatedUnion('action', [
	z.object({ action: z.literal('set_visibility'), visibility: z.enum(['public', 'private']) }),
	z.object({ action: z.literal('move'), direction: z.enum(['up', 'down']) }),
	z.object({ action: z.literal('archive') }),
	z.object({ action: z.literal('restore') }),
	z.object({
		action: z.literal('confirm_website'),
		pending_since: z.iso.datetime({ offset: true })
	})
]);

export type PackageCatalogAction = z.infer<typeof packageCatalogActionSchema>;

// Package builder P11b: Jafar's offer builder. The limits mirror save_package_offer, which re-checks them,
// so a bad value is explained next to its field here rather than refused there.
export const packageOfferIdSchema = z.string().uuid('The offer identifier is invalid.');

export const packageOfferTermsSchema = z
	.object({
		name: z
			.string()
			.trim()
			.min(1, 'Give the offer a name.')
			.max(80, 'Keep the name under 80 characters.'),
		apply_mode: z.enum(['automatic', 'code']),
		code: z
			.string()
			.trim()
			.toUpperCase()
			.nullish()
			.transform((code) => code || null),
		discount_kind: z.enum(['percent', 'fixed']),
		percent_off: z
			.number()
			.int('Enter a whole percentage.')
			.min(1, 'A percentage discount is from 1 to 100.')
			.max(100, 'A percentage discount is from 1 to 100.')
			.nullable(),
		amount_off_usd_cents: z
			.number()
			.int('Enter an amount in dollars and cents.')
			.min(1, 'Enter the amount taken off.')
			.max(100_000_000, 'Enter an amount under $1,000,000.')
			.nullable(),
		applies_to_monthly: z.boolean(),
		applies_to_yearly: z.boolean(),
		monthly_periods: z
			.number()
			.int('Enter a whole number of months.')
			.min(1, 'Choose from 1 to 36 months.')
			.max(36, 'Choose from 1 to 36 months.')
			.nullable(),
		customer_eligibility: z.enum(['new', 'existing', 'any']),
		claim_starts_at: z.iso.datetime({ offset: true, message: 'Choose when claims open.' }),
		claim_ends_at: z.iso.datetime({ offset: true }).nullable(),
		redemption_cap: z
			.number()
			.int('Enter a whole number.')
			.min(1, 'A cap is at least 1 customer.')
			.max(1_000_000, 'Enter a cap under 1,000,000.')
			.nullable(),
		package_ids: z
			.array(packageIdSchema)
			.min(1, 'Choose at least one package.')
			.max(100, 'Choose 100 packages or fewer.')
	})
	.superRefine((offer, ctx) => {
		if (offer.apply_mode === 'code') {
			if (!offer.code)
				ctx.addIssue({ code: 'custom', path: ['code'], message: 'Give the offer a code.' });
			else if (!/^[A-Z0-9][A-Z0-9-]{2,31}$/.test(offer.code))
				ctx.addIssue({
					code: 'custom',
					path: ['code'],
					message: 'A code is 3 to 32 letters, numbers, or dashes.'
				});
		}
		if (offer.discount_kind === 'percent' && offer.percent_off === null)
			ctx.addIssue({
				code: 'custom',
				path: ['percent_off'],
				message: 'Enter the percentage taken off.'
			});
		if (offer.discount_kind === 'fixed' && offer.amount_off_usd_cents === null)
			ctx.addIssue({
				code: 'custom',
				path: ['amount_off_usd_cents'],
				message: 'Enter the amount taken off.'
			});
		if (!offer.applies_to_monthly && !offer.applies_to_yearly)
			ctx.addIssue({
				code: 'custom',
				path: ['applies_to_monthly'],
				message: 'Choose monthly billing, yearly billing, or both.'
			});
		if (offer.applies_to_monthly && offer.monthly_periods === null)
			ctx.addIssue({
				code: 'custom',
				path: ['monthly_periods'],
				message: 'Choose how many months the offer lasts.'
			});
		if (offer.claim_ends_at && Date.parse(offer.claim_ends_at) <= Date.parse(offer.claim_starts_at))
			ctx.addIssue({
				code: 'custom',
				path: ['claim_ends_at'],
				message: 'The last claim day must come after the first.'
			});
	});

export type PackageOfferTerms = z.infer<typeof packageOfferTermsSchema>;

export const createPackageOfferSchema = z.object({
	idempotency_key: z.string().uuid('Open the dialog again and try once more.'),
	terms: packageOfferTermsSchema
});

export const packageOfferActionSchema = z.discriminatedUnion('action', [
	z.object({
		action: z.literal('save'),
		expected_revision: z.number().int().positive(),
		terms: packageOfferTermsSchema
	}),
	z.object({ action: z.literal('archive') }),
	z.object({ action: z.literal('restore') })
]);
