import { z } from 'zod';

// Money crosses this boundary as whole minor units — cents, never dollars, never a float. The ceilings
// mirror the database's own checks so a bad number is a field error on the form instead of a raw
// constraint violation coming back from a write function.
const MINOR_UNIT_MAX = 1_000_000_000_000;
const QUANTITY_MAX = 1_000_000;

export const PRICING_LINE_MAX = 200;

export const PRICING_CATEGORIES = ['product', 'service'] as const;
export type PricingCategory = (typeof PRICING_CATEGORIES)[number];

const minorAmount = (label: string) =>
	z
		.number()
		.int(`Enter ${label} in whole cents.`)
		.min(0, `${label} cannot be negative.`)
		.max(MINOR_UNIT_MAX, `That ${label} is too large.`);

// The column is numeric(12,3), so anything finer than a thousandth would be silently rounded on the way
// in and the browser would show a different number than the one it sent.
const quantity = z
	.number()
	.finite()
	.gt(0, 'Enter a quantity above zero.')
	.max(QUANTITY_MAX, 'That quantity is too large.')
	.refine((value) => Math.abs(value * 1000 - Math.round(value * 1000)) < 1e-6, {
		message: 'A quantity can have at most three decimal places.'
	});

const optionalText = (max: number, message: string) =>
	z
		.string()
		.trim()
		.max(max, message)
		.nullish()
		.transform((value) => value || null);

// The same field on an edit, where leaving it out has to mean "do not touch this" rather than "clear it".
// Sending an explicit null is how the form clears one.
const patchableText = (max: number, message: string) =>
	z
		.string()
		.trim()
		.max(max, message)
		.nullable()
		.optional()
		.transform((value) => (value === undefined ? undefined : value || null));

const lineName = z
	.string()
	.trim()
	.min(2, 'Give this line a name.')
	.max(160, 'That name is too long. Keep it under 160 characters.');

const unitLabel = optionalText(24, 'Keep the unit under 24 characters.');
const longDescription = optionalText(2000, 'That description is too long.');

// Labor is a service with a flag on it, not a second pricing engine — the flag only decides which part of
// the form the row appears in. The database says the same thing in a check constraint.
const laborIsService = {
	rule: (value: { is_labor: boolean; category: PricingCategory }) =>
		!value.is_labor || value.category === 'service',
	options: { message: 'Labor is always a service.', path: ['category'] }
};

// One priced row on a request. `catalog_item_id` is provenance only: null means somebody typed a one-off
// line, and a filled id is checked against the live catalog by the write function, not here.
const requestPricingLineSchema = z
	.object({
		name: lineName,
		category: z.enum(PRICING_CATEGORIES),
		is_labor: z.boolean().default(false),
		catalog_item_id: z
			.string()
			.uuid()
			.nullish()
			.transform((value) => value ?? null),
		description: longDescription,
		unit_label: unitLabel,
		quantity,
		unit_price_minor: minorAmount('a price'),
		unit_cost_minor: minorAmount('a cost'),
		is_taxable: z.boolean().default(true),
		// Set by the browser right after it uploads a photo for this request, ahead of Save. The write
		// function is what actually checks the photo belongs to this request — not this schema.
		image_attachment_id: z
			.string()
			.uuid()
			.nullish()
			.transform((value) => value ?? null)
	})
	.refine(laborIsService.rule, laborIsService.options);

// The whole set is sent every time, because that is how people actually edit a price table: they retype,
// reorder, and delete rows before saving once. `expected_revision` is the copy the browser read; the write
// function refuses a stale one rather than letting the second saver overwrite the first.
export const replaceRequestPricingSchema = z.object({
	expected_revision: z.number().int().min(0, 'Reload the pricing and try again.'),
	lines: z
		.array(requestPricingLineSchema)
		.max(PRICING_LINE_MAX, `A request can hold up to ${PRICING_LINE_MAX} lines.`)
});

// The fingerprint of what the person was looking at when they pressed the button. A retry carrying the
// same key and the same fingerprint gets the first quote back; a changed one is a conflict, not a silent
// second conversion.
export const convertRequestToQuoteSchema = z.object({
	idempotency_key: z.string().uuid('Start a new action and try again.'),
	request_hash: z
		.string()
		.trim()
		.min(1, 'Reload the request and try again.')
		.max(200, 'Reload the request and try again.')
});

// A quote's lines start from the request's shape — the same block edits both — and add what only a quote
// has: whether the line is priced work or just words, and whether the customer must take it or may take it.
export const QUOTE_LINE_KINDS = ['priced', 'text', 'heading'] as const;
export const QUOTE_SELECTION_KINDS = ['required', 'optional'] as const;

const quoteChoiceShape = {
	line_kind: z.enum(QUOTE_LINE_KINDS).default('priced'),
	selection_kind: z.enum(QUOTE_SELECTION_KINDS).default('required'),
	is_recommended: z.boolean().default(false)
};

// A heading or a note is words on the page: a name, maybe a sentence under it, and nothing else. Money
// fields are not merely ignored here, they are refused, so a total can never come from a line of text.
const quoteTextLineSchema = z.object({
	line_kind: z.enum(['text', 'heading']),
	name: lineName,
	description: longDescription
});

const quotePricedLineSchema = requestPricingLineSchema.and(z.object(quoteChoiceShape));

const quoteLineSchema = z
	.union([quoteTextLineSchema, quotePricedLineSchema])
	.superRefine((value, context) => {
		if (!('selection_kind' in value)) return;
		if (value.is_recommended && value.selection_kind !== 'optional') {
			context.addIssue({
				code: z.ZodIssueCode.custom,
				message: 'Only an add-on can be recommended.',
				path: ['is_recommended']
			});
		}
	});

export const replaceQuoteLinesSchema = z.object({
	expected_revision: z.number().int().min(1, 'Reload the quote and try again.'),
	lines: z
		.array(quoteLineSchema)
		.max(PRICING_LINE_MAX, `A quote can hold up to ${PRICING_LINE_MAX} lines.`)
});

const expectedRevision = z.number().int().min(1, 'Reload the quote and try again.');

// One discount, named the way the customer will read it. Sending a null type is the Remove button, and the
// name and value go with it.
export const quoteDiscountSchema = z.object({
	expected_revision: expectedRevision,
	name: z
		.string()
		.trim()
		.min(1, 'Give this discount a name.')
		.max(80, 'Keep the name under 80 characters.')
		.nullable()
		.optional()
		.transform((value) => value || null),
	type: z.enum(['fixed', 'percentage']).nullable(),
	// A percentage is basis points, so 12.5% arrives as 1250 and nothing is lost on the way in.
	value: z
		.number()
		.int('Enter a whole amount.')
		.min(0, 'A discount cannot be negative.')
		.max(MINOR_UNIT_MAX, 'That discount is too large.')
		.nullable()
		.optional()
		.transform((value) => value ?? null)
});

// Reset to whatever the business default or the property's own pin currently resolves to, freeze one
// chosen saved rate, say explicitly there is no tax, or freeze a one-off name and percentage — and, only
// for a custom rate, optionally save it to the shared list. `save_as_reusable` is checked against
// 'settings.taxes.manage' by the database itself: pricing a quote is not managing Settings → Taxes.
export const QUOTE_TAX_SOURCES = [
	'business_default',
	'property_default',
	'saved_rate',
	'no_tax',
	'custom'
] as const;

export const quoteTaxSchema = z
	.object({
		expected_revision: expectedRevision,
		source: z.enum(QUOTE_TAX_SOURCES, { message: 'Choose a tax option.' }),
		rate_id: z
			.string()
			.uuid()
			.nullish()
			.transform((value) => value ?? null),
		custom_name: z
			.string()
			.trim()
			.min(1, 'Give this tax a name the customer will recognize.')
			.max(80, 'Keep the name under 80 characters.')
			.nullish()
			.transform((value) => value || null),
		custom_rate_basis_points: z
			.number()
			.int('Enter the rate in basis points.')
			.gt(0, 'A tax rate is greater than 0%.')
			.max(10000, 'A tax rate cannot be more than 100%.')
			.nullish()
			.transform((value) => value ?? null),
		save_as_reusable: z.boolean().default(false)
	})
	.refine((value) => value.source !== 'saved_rate' || value.rate_id !== null, {
		path: ['rate_id'],
		message: 'Choose a saved tax rate.'
	})
	.refine((value) => value.source !== 'custom' || value.custom_name !== null, {
		path: ['custom_name'],
		message: 'Give this tax a name the customer will recognize.'
	})
	.refine((value) => value.source !== 'custom' || value.custom_rate_basis_points !== null, {
		path: ['custom_rate_basis_points'],
		message: 'Enter a tax rate.'
	});

// One installment on a deposit-only or schedule deposit. `value` is whole cents for a fixed installment,
// basis points for a percentage one — the write function prices it and refuses the save if a schedule's
// installments do not sum to the draft's current total.
const quoteDepositScheduleItemSchema = z.object({
	description: z
		.string()
		.trim()
		.min(2, 'Give this installment a description.')
		.max(160, 'Keep the description under 160 characters.'),
	type: z.enum(['fixed', 'percentage']),
	value: z
		.number()
		.int('Enter a whole amount.')
		.min(1, 'Enter an amount above zero.')
		.max(MINOR_UNIT_MAX, 'That amount is too large.')
});

// The whole deposit shape sent at once, the same way lines are — staff add, reorder, and remove
// installments before saving once. `deposit_type` null is the Remove button, and every installment goes
// with it.
export const quoteDepositSchema = z.object({
	expected_revision: expectedRevision,
	deposit_type: z.enum(['deposit_only', 'schedule']).nullable(),
	items: z
		.array(quoteDepositScheduleItemSchema)
		.max(12, 'A payment schedule can hold up to 12 installments.')
});

export const QUOTE_DEPOSIT_METHODS = ['cash', 'check', 'other'] as const;
export type QuoteDepositMethod = (typeof QUOTE_DEPOSIT_METHODS)[number];

// Recording money that changed hands off the app. The idempotency key is the same shape every other
// campaign ledger uses — minted once per dialog open, replayed instead of duplicated on a retry.
export const recordQuoteDepositEventSchema = z.object({
	idempotency_key: z.string().uuid('Start a new action and try again.'),
	method: z.enum(QUOTE_DEPOSIT_METHODS, { message: 'Choose how the deposit was received.' }),
	reference: optionalText(200, 'Keep the reference under 200 characters.'),
	note: optionalText(500, 'Keep the note under 500 characters.')
});

// A correction, not an undo. A reason is always required, unlike the note on the original receipt.
export const reverseQuoteDepositEventSchema = z.object({
	idempotency_key: z.string().uuid('Start a new action and try again.'),
	reason: z
		.string()
		.trim()
		.min(1, 'Say why this deposit is being reversed.')
		.max(500, 'Keep the reason under 500 characters.')
});

export const quoteVisibilitySchema = z.object({
	expected_revision: expectedRevision,
	show_quantities: z.boolean(),
	show_unit_prices: z.boolean(),
	show_line_totals: z.boolean(),
	show_totals: z.boolean()
});

export const quoteCopySchema = z.object({
	expected_revision: expectedRevision,
	introduction: optionalText(10000, 'That introduction is too long.'),
	client_message: optionalText(5000, 'That client message is too long.')
});

// Which files already on this quote belong in the customer's copy. The files themselves are not touched.
export const quoteVersionAttachmentsSchema = z.object({
	expected_revision: expectedRevision,
	attachments: z
		.array(
			z.object({
				attachment_id: z.string().uuid('That file could not be found.'),
				display_name: z
					.string()
					.trim()
					.min(1, 'Give this file a name.')
					.max(255, 'Keep the name under 255 characters.'),
				customer_visible: z.boolean().default(false)
			})
		)
		.max(50, 'A quote can show up to 50 files.')
});

// Pricing a what-if. It records nothing, so it carries no revision.
export const quotePreviewSchema = z.object({
	addon_ids: z.array(z.string().uuid()).max(PRICING_LINE_MAX).default([])
});

const quoteTitle = z
	.string()
	.trim()
	.min(2, 'Give this quote a title.')
	.max(160, 'That title is too long. Keep it under 160 characters.');

const contractDisclaimer = optionalText(5000, 'That contract disclaimer is too long.');

// Client and property are ids the picker already chose from. The write function still checks the property
// belongs to the client and that both are live, because a form can send anything.
export const createQuoteSchema = z.object({
	client_id: z.string().uuid('Choose a client.'),
	property_id: z.string().uuid('Choose a property.'),
	title: quoteTitle,
	contract_disclaimer: contractDisclaimer
});

export const updateQuoteDraftSchema = z.object({
	expected_revision: z.number().int().min(1, 'Reload the quote and try again.'),
	title: quoteTitle,
	contract_disclaimer: contractDisclaimer
});

// Only an approved quote needs a reason, and only the write function knows the status, so the reason is
// optional here and required there.
export const archiveQuoteSchema = z.object({
	reason: optionalText(500, 'Keep the reason under 500 characters.')
});

// A list selection, not a filter - the same size ceiling the list page's own page size sits under.
export const bulkArchiveQuotesSchema = z.object({
	ids: z
		.array(z.string().uuid())
		.min(1, 'Select at least one quote.')
		.max(100, 'Select fewer quotes.')
});

// Part 5A lifecycle. Publishing names the revision the browser was looking at, so a second click on a
// slow network lands on the version that already exists instead of making another one. Revise carries no
// body at all: the quote itself says which version it is cloning.
export const publishQuoteSchema = z.object({
	expected_revision: expectedRevision
});

export const quoteEmailSchema = z.strictObject({
	idempotency_key: z.string().uuid('Start a new email attempt and try again.')
});

// The quote, recipient, sender, content, and secure link all come from current server-side authority.
// The browser can only identify one logical click, which makes a retry safe without opening a second email.
// Recording an answer the customer gave off the app. `expected_revision` is only needed when the quote is
// still a draft, because answering one publishes it first; the write function decides whether it matters.
export const recordQuoteDecisionSchema = z.object({
	decision: z.enum(['approved', 'declined'], {
		message: 'A decision is either approved or declined.'
	}),
	note: optionalText(1000, 'Keep the note under 1000 characters.'),
	expected_revision: expectedRevision.optional()
});

// The status list itself lives in `$lib/quotes/statuses.ts` so the browser can read it too. Re-exported
// here because every server route already asks this schema what a quote status is.
export { STORED_QUOTE_STATUSES } from '$lib/quotes/statuses';
export type { StoredQuoteStatus } from '$lib/quotes/statuses';

export const QUOTE_PAGE_SIZE_DEFAULT = 25;
export const QUOTE_PAGE_SIZE_MAX = 50;

// Both sorts are index-backed: created walks quotes_organization_created_idx and number walks the
// existing quotes_number_unique. Nothing else is offered, so the list can never fall back to sorting a
// whole tenant's quotes in memory.
export const QUOTE_SORT_KEYS = ['created', 'number'] as const;

export const quoteListQuerySchema = z.object({
	search: z
		.string()
		.trim()
		.max(160)
		.optional()
		.transform((value) => value || ''),
	status: z.string().trim().max(200).optional(),
	sort: z.enum(QUOTE_SORT_KEYS).default('created'),
	dir: z.enum(['asc', 'desc']).default('desc'),
	created_from: z.string().datetime({ offset: true }).optional(),
	created_to: z.string().datetime({ offset: true }).optional(),
	cursor: z.string().min(3).max(400).optional(),
	limit: z.coerce.number().int().min(1).max(QUOTE_PAGE_SIZE_MAX).default(QUOTE_PAGE_SIZE_DEFAULT)
});

const catalogItemShape = {
	category: z.enum(PRICING_CATEGORIES),
	name: lineName,
	description: longDescription,
	unit_label: unitLabel,
	unit_price_minor: minorAmount('a price').default(0),
	unit_cost_minor: minorAmount('a cost').default(0),
	is_taxable: z.boolean().default(true),
	is_labor: z.boolean().default(false)
};

export const catalogItemCreateSchema = z
	.object(catalogItemShape)
	.refine(laborIsService.rule, laborIsService.options);

// Editing sends whichever fields changed, plus `archived` on its own for the archive toggle. Archiving is
// never a delete: request lines and quote copies still point back at the item they came from.
export const catalogItemUpdateSchema = z
	.object({
		category: catalogItemShape.category.optional(),
		name: lineName.optional(),
		description: patchableText(2000, 'That description is too long.'),
		unit_label: patchableText(24, 'Keep the unit under 24 characters.'),
		unit_price_minor: minorAmount('a price').optional(),
		unit_cost_minor: minorAmount('a cost').optional(),
		is_taxable: z.boolean().optional(),
		is_labor: z.boolean().optional(),
		archived: z.boolean().optional()
	})
	.refine((value) => Object.values(value).some((field) => field !== undefined), {
		message: 'Nothing to change.',
		path: ['name']
	})
	.refine((value) => !value.is_labor || value.category !== 'product', laborIsService.options);

export const CATALOG_PAGE_SIZE_DEFAULT = 25;
export const CATALOG_PAGE_SIZE_MAX = 50;

// The three sort orders the Settings list offers. Name walks the picker's own
// `catalog_items_organization_name_idx`; price and updated each have a dedicated partial index added
// alongside `settings.price_book.manage` -- see the Part 2B migration.
export const CATALOG_SORT_KEYS = ['name', 'price', 'updated'] as const;
export type CatalogSortKey = (typeof CATALOG_SORT_KEYS)[number];

// The picker and the settings list read the same route. Both walk an `organization_id` + sort-column +
// `id` index, so paging is keyset on "<sort column's value>|<id>", never offset.
export const catalogListQuerySchema = z.object({
	// Name search stayed name-only for the picker; the settings list also searches the description, so
	// both terms are tried together and neither claims an index it does not have.
	search: z
		.string()
		.trim()
		.max(160)
		.optional()
		.transform((value) => value || ''),
	category: z.enum(PRICING_CATEGORIES).optional(),
	labor: z.enum(['only', 'exclude']).optional(),
	taxable: z.enum(['only', 'exclude']).optional(),
	include_archived: z
		.enum(['true', 'false'])
		.default('false')
		.transform((value) => value === 'true'),
	sort: z.enum(CATALOG_SORT_KEYS).default('name'),
	dir: z.enum(['asc', 'desc']).default('asc'),
	cursor: z.string().min(3).max(400).optional(),
	limit: z.coerce
		.number()
		.int()
		.min(1)
		.max(CATALOG_PAGE_SIZE_MAX)
		.default(CATALOG_PAGE_SIZE_DEFAULT)
});

// Settings management: the whole item replaces itself every time a manager saves, the same full-replace
// shape Taxes uses -- never the picker's per-field PATCH.
export const priceBookExpectedRevision = z.number().int().min(1, 'Reload this item and try again.');

export const priceBookItemUpdateSchema = z
	.object({ expected_revision: priceBookExpectedRevision, ...catalogItemShape })
	.refine(laborIsService.rule, laborIsService.options);

export const priceBookItemDeleteSchema = z.object({
	expected_revision: priceBookExpectedRevision
});

// Issuing a customer link takes no fields at all: the recipient comes from the client's own email inside
// the write function, and the version comes from whatever is currently published. The empty strict object
// is the check — a body trying to name an inbox or a version is refused here rather than ignored.
export const issueQuoteAccessLinkSchema = z.strictObject({});

// The customer's own two calls. Both bodies are strict: this is the only unauthenticated write path in
// the app, so a field nobody expected is refused here rather than quietly dropped.
//
// Recording a view takes nothing at all. Everything it needs - which link, which quote, which version -
// is already decided by the token in the URL.
export const quoteCustomerViewSchema = z.strictObject({});

// A signature is a name plus, when they drew it, the picture. The picture's own bytes are checked in
// `$lib/server/quotes/signatures.ts`; this only refuses a body that is the wrong shape before any of that
// work starts. The base64 ceiling allows for the third that encoding adds to the file.
const SIGNATURE_DATA_URL_MAX = Math.ceil((200 * 1024 * 4) / 3) + 64;

const signatureImageField = z
	.string()
	.max(SIGNATURE_DATA_URL_MAX, 'That signature is too large.')
	.regex(/^data:image\/png;base64,[A-Za-z0-9+/]+={0,2}$/, 'That signature could not be read.');

const signerName = z
	.string()
	.trim()
	.min(1, 'Type the name of the person signing.')
	.max(120, 'That name is too long.');

// Drawn means there is a drawing, typed means there is not. Anything else is a body that half-agrees with
// itself, and the database refuses the same pairing - this just says so in the customer's words first.
function signatureShapeIsWhole(value: { method: string; image?: string }) {
	return (value.method === 'typed') === (value.image === undefined);
}

const SIGNATURE_SHAPE_MESSAGE = 'That signature is incomplete.';

export const quoteCustomerSignatureSchema = z
	.strictObject({
		name: signerName,
		method: z.enum(['typed', 'drawn'], { message: 'That is not a way to sign.' }),
		image: signatureImageField.optional()
	})
	.refine(signatureShapeIsWhole, { message: SIGNATURE_SHAPE_MESSAGE, path: ['image'] });

// Signing is offered, never demanded: Jobber's own default, and Jafar's call. Approve with a name, with a
// drawing, or with neither.
export const quoteCustomerApprovalSchema = z.strictObject({
	note: z.string().trim().min(1).max(1000).optional(),
	signature: quoteCustomerSignatureSchema.optional()
});

// The staff pad. Jobber's Collect Signature is the in-person close, so the body carries the signature and
// nothing about status: signing in person is what approves the quote. `expected_revision` only matters
// when the quote is still a draft, because signing one publishes it first.
export const collectQuoteSignatureSchema = z
	.strictObject({
		name: signerName,
		method: z.enum(['typed', 'in_person'], { message: 'That is not a way to sign.' }),
		image: signatureImageField.optional(),
		note: optionalText(1000, 'Keep the note under 1000 characters.'),
		expected_revision: expectedRevision.optional()
	})
	.refine(signatureShapeIsWhole, { message: SIGNATURE_SHAPE_MESSAGE, path: ['image'] });

// Asking for changes without saying what to change gives the office nothing to act on, so the message is
// the point of the request rather than an extra.
export const quoteCustomerChangeRequestSchema = z.strictObject({
	note: z
		.string()
		.trim()
		.min(3, 'Tell them what you would like changed.')
		.max(1000, 'That message is too long.')
});
