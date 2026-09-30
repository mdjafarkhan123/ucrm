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
