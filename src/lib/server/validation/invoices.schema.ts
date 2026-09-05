import { z } from 'zod';
import { PRICING_CATEGORIES, QUOTE_TAX_SOURCES } from '$lib/server/validation/quotes.schema';

// The status vocabulary lives in `$lib/invoices/statuses.ts` so the browser reads the same list the server
// validates against. Re-exported here because every invoice route already asks this schema.
export { INVOICE_DERIVED_STATUSES, INVOICE_FILTERABLE_STATUSES } from '$lib/invoices/statuses';
export type { InvoiceDerivedStatus } from '$lib/invoices/statuses';

import { INVOICE_DERIVED_STATUSES } from '$lib/invoices/statuses';

export const INVOICE_PAGE_SIZE_DEFAULT = 25;
export const INVOICE_PAGE_SIZE_MAX = 50;

// Both sorts are index-backed: created walks invoices_organization_created_idx and number walks the existing
// invoices_number_unique. Nothing else is offered, so the list can never fall back to sorting a whole
// tenant's invoices in memory.
export const INVOICE_SORT_KEYS = ['created', 'number'] as const;

export const invoiceListQuerySchema = z.object({
	search: z
		.string()
		.trim()
		.max(160)
		.optional()
		.transform((value) => value || ''),
	/** Comma-joined derived statuses, e.g. `past_due,awaiting_payment`. */
	status: z.string().trim().max(200).optional(),
	sort: z.enum(INVOICE_SORT_KEYS).default('created'),
	dir: z.enum(['asc', 'desc']).default('desc'),
	created_from: z.string().datetime({ offset: true }).optional(),
	created_to: z.string().datetime({ offset: true }).optional(),
	cursor: z.string().min(3).max(400).optional(),
	limit: z.coerce
		.number()
		.int()
		.min(1)
		.max(INVOICE_PAGE_SIZE_MAX)
		.default(INVOICE_PAGE_SIZE_DEFAULT)
});

export function readInvoiceStatusFilter(raw: string | undefined) {
	return (raw ?? '')
		.split(',')
		.map((value) => value.trim())
		.filter((value): value is (typeof INVOICE_DERIVED_STATUSES)[number] =>
			(INVOICE_DERIVED_STATUSES as readonly string[]).includes(value)
		);
}

// --- Writing invoices (Part 4b) ---------------------------------------------------------------------------

// Money and quantity ceilings mirror the database's own checks on invoice_lines, so a bad number is a field
// error on the form rather than a raw constraint violation coming back from the write command.
const MINOR_UNIT_MAX = 1_000_000_000_000;
const QUANTITY_MAX = 1_000_000;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

// An invoice carries up to 100 lines, matching the job scope it can be built from and the table's own limit.
export const INVOICE_LINE_MAX = 100;

const invoiceMinorAmount = (label: string) =>
	z
		.number()
		.int(`Enter ${label} in whole cents.`)
		.min(0, `${label} cannot be negative.`)
		.max(MINOR_UNIT_MAX, `That ${label} is too large.`);

const invoiceQuantity = z
	.number()
	.finite()
	.gt(0, 'Enter a quantity above zero.')
	.max(QUANTITY_MAX, 'That quantity is too large.')
	.refine((value) => Math.abs(value * 1000 - Math.round(value * 1000)) < 1e-6, {
		message: 'A quantity can have at most three decimal places.'
	});

// One priced invoice line. An invoice bills priced product or service work; unlike a quote it carries no
// headings, notes, optional add-ons, or internal cost/markup. A service date may ride along (mainly for a
// Job-generated invoice); a direct invoice leaves it null.
const invoiceLineSchema = z.object({
	position: z.number().int().min(0),
	category: z.enum(PRICING_CATEGORIES),
	source_catalog_item_id: z
		.string()
		.uuid()
		.nullish()
		.transform((value) => value ?? null),
	name: z
		.string()
		.trim()
		.min(2, 'Give this line a name.')
		.max(160, 'That name is too long. Keep it under 160 characters.'),
	description: z
		.string()
		.trim()
		.max(2000, 'That description is too long.')
		.nullish()
		.transform((value) => value || null),
	unit_label: z
		.string()
		.trim()
		.max(24, 'Keep the unit under 24 characters.')
		.nullish()
		.transform((value) => value || null),
	quantity: invoiceQuantity,
	unit_price_minor: invoiceMinorAmount('a price'),
	is_taxable: z.boolean().default(true),
	service_date: z
		.string()
		.regex(ISO_DATE, 'Pick a valid service date.')
		.nullish()
		.transform((value) => value || null)
});

// Terms resolve one of two ways, never both: a named payment term (or none, which lets the command fall back
// to the client/account default) or a custom due date. The pairing is checked here so a person hears about it
// on the form before the command refuses it.
const termFields = {
	payment_term_id: z
		.string()
		.uuid()
		.nullish()
		.transform((value) => value ?? null),
	custom_due_date: z
		.string()
		.regex(ISO_DATE, 'Pick a valid due date.')
		.nullish()
		.transform((value) => value || null)
};
const oneTermChoice = (body: { payment_term_id: string | null; custom_due_date: string | null }) =>
	!(body.payment_term_id && body.custom_due_date);

// Creating a draft invoice directly. The invoice number, snapshots, due date and money all come from the
// command; nothing here guesses at them. The idempotency key and fingerprint let a double click or a retried
// request return the first invoice rather than a second one.
export const createInvoiceSchema = z
	.object({
		client_id: z.string().uuid('Choose a client to continue.'),
		subject: z
			.string()
			.trim()
			.min(2, 'Give this invoice a subject.')
			.max(160, 'That subject is too long. Keep it under 160 characters.'),
		lines: z
			.array(invoiceLineSchema)
			.min(1, 'An invoice needs at least one line.')
			.max(INVOICE_LINE_MAX, `An invoice can hold up to ${INVOICE_LINE_MAX} lines.`),
		service_property_ids: z.array(z.string().uuid()).max(50).default([]),
		issue_date: z
			.string()
			.regex(ISO_DATE, 'Pick a valid invoice date.')
			.nullish()
			.transform((value) => value || null),
		...termFields,
		idempotency_key: z.string().uuid('Start a new action and try again.'),
		request_hash: z
			.string()
			.trim()
			.min(1, 'Reload the form and try again.')
			.max(200, 'Reload the form and try again.')
	})
	.refine(oneTermChoice, {
		message: 'Choose either a payment term or a custom due date, not both.',
		path: ['custom_due_date']
	});

export type CreateInvoiceInput = z.infer<typeof createInvoiceSchema>;

// Editing a draft's subject, invoice date and terms. `expected_revision` is the revision the browser last
// read; a stale one is refused so two people editing the same invoice cannot silently overwrite each other.
export const updateInvoiceDetailsSchema = z
	.object({
		expected_revision: z.number().int().min(0),
		subject: z
			.string()
			.trim()
			.min(2, 'Give this invoice a subject.')
			.max(160, 'That subject is too long. Keep it under 160 characters.'),
		issue_date: z
			.string()
			.regex(ISO_DATE, 'Pick a valid invoice date.')
			.nullish()
			.transform((value) => value || null),
		...termFields
	})
	.refine(oneTermChoice, {
		message: 'Choose either a payment term or a custom due date, not both.',
		path: ['custom_due_date']
	});

export type UpdateInvoiceDetailsInput = z.infer<typeof updateInvoiceDetailsSchema>;

// The whole set of lines in one save, the same all-or-nothing replacement a job's scope uses. Positions come
// from the browser's order; the command renumbers them from zero so a gap or a duplicate cannot survive.
export const replaceInvoiceLinesSchema = z.object({
	expected_revision: z.number().int().min(0),
	lines: z
		.array(invoiceLineSchema)
		.min(1, 'An invoice needs at least one line.')
		.max(INVOICE_LINE_MAX, `An invoice can hold up to ${INVOICE_LINE_MAX} lines.`)
});

// One discount on the invoice. A null type removes it, which is why the name and value are optional here and
// the pairing is checked instead of each field on its own.
export const setInvoiceDiscountSchema = z
	.object({
		expected_revision: z.number().int().min(0),
		type: z.enum(['fixed', 'percentage']).nullish(),
		name: z
			.string()
			.trim()
			.max(80, 'That discount name is too long.')
			.nullish()
			.transform((value) => value || null),
		value: z.number().int().min(0).max(MINOR_UNIT_MAX).nullish()
	})
	.refine((body) => !body.type || Boolean(body.name), {
		message: 'Give this discount a name the customer will recognize.',
		path: ['name']
	})
	.refine((body) => !body.type || typeof body.value === 'number', {
		message: 'Enter how much comes off.',
		path: ['value']
	})
	.refine((body) => body.type !== 'percentage' || (body.value ?? 0) <= 10_000, {
		message: 'A percentage discount is between 0 and 100 percent.',
		path: ['value']
	});

// Tax resolved the same five ways a quote or job resolves it — literally the same list, so the three screens
// can never offer different options. `set_invoice_tax` derives the property from the invoice's first service
// property itself and, unlike the job command, does not persist a one-off rate to the shared list, so the
// `save_as_reusable` flag the shared card sends is accepted here and simply ignored by the route.
export const setInvoiceTaxSchema = z
	.object({
		expected_revision: z.number().int().min(0),
		source: z.enum(QUOTE_TAX_SOURCES, { message: 'Choose a tax option.' }),
		rate_id: z
			.string()
			.uuid()
			.nullish()
			.transform((value) => value ?? null),
		custom_name: z
			.string()
			.trim()
			.max(80, 'That tax name is too long.')
			.nullish()
			.transform((value) => value || null),
		custom_rate_basis_points: z.number().int().min(1).max(10_000).nullish(),
		save_as_reusable: z.boolean().default(false)
	})
	.refine((body) => body.source !== 'saved_rate' || Boolean(body.rate_id), {
		message: 'Choose a saved tax rate.',
		path: ['rate_id']
	})
	.refine((body) => body.source !== 'custom' || Boolean(body.custom_name), {
		message: 'Give this tax a name the customer will recognize.',
		path: ['custom_name']
	})
	.refine((body) => body.source !== 'custom' || typeof body.custom_rate_basis_points === 'number', {
		message: 'Enter a tax rate.',
		path: ['custom_rate_basis_points']
	});

// Issuing a draft. "Mark as Sent" issues it with no transport (`marked_sent`); sending it by email is
// `sent`, which arrives with Communications in a later part. Both are accepted so the same command serves
// both; the idempotency key makes a double click return the first result.
export const issueInvoiceSchema = z.object({
	expected_revision: z.number().int().min(0),
	method: z.enum(['sent', 'marked_sent']).default('marked_sent'),
	idempotency_key: z.string().uuid('Start a new action and try again.'),
	request_hash: z.string().trim().min(1, 'Reload and try again.').max(200, 'Reload and try again.')
});

// Deleting a draft. Only the revision the browser last read, plus the idempotency key and fingerprint so a
// retried delete returns the first result rather than erroring on the already-gone invoice.
export const deleteInvoiceSchema = z.object({
	expected_revision: z.number().int().min(0),
	idempotency_key: z.string().uuid('Start a new action and try again.'),
	request_hash: z.string().trim().min(1, 'Reload and try again.').max(200, 'Reload and try again.')
});
