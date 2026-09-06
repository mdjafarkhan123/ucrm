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

// The ready-to-bill queue is deliberately narrower than the Invoices list: it is ordered one way — oldest
// unpaid-for work first — because "what has been waiting longest" is the only question a billing queue is
// asked. No sort keys, no status filter, no client filter.
export const readyToBillQuerySchema = z.object({
	search: z
		.string()
		.trim()
		.max(160)
		.optional()
		.transform((value) => value || ''),
	/** `<oldest due date>|<reminder id>`, the pair the queue's keyset seek reads. */
	cursor: z.string().min(3).max(120).optional(),
	limit: z.coerce
		.number()
		.int()
		.min(1)
		.max(INVOICE_PAGE_SIZE_MAX)
		.default(INVOICE_PAGE_SIZE_DEFAULT)
});

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

// One piece of billable work the new invoice claims. The four kinds are the ones `invoice_sources` stores,
// and the command re-checks every relationship itself; this only proves the shape is one the command can read.
// A whole job carries nothing but its job, which is why the extra references are optional here rather than
// branched per kind — `claim_invoice_sources` owns that rule and states it in the contractor's words.
const invoiceSourceSchema = z.object({
	kind: z.enum(['job_total', 'visit', 'reminder_period', 'installment']),
	job_id: z.string().uuid('Every piece of work belongs to a job.'),
	visit_id: z
		.string()
		.uuid()
		.nullish()
		.transform((value) => value ?? null),
	reminder_id: z
		.string()
		.uuid()
		.nullish()
		.transform((value) => value ?? null),
	installment_number: z
		.number()
		.int()
		.min(1)
		.nullish()
		.transform((value) => value ?? null),
	service_property_index: z
		.number()
		.int()
		.min(0)
		.nullish()
		.transform((value) => value ?? null)
});

// Creating a draft invoice directly. The invoice number, snapshots, due date and money all come from the
// command; nothing here guesses at them. The idempotency key and fingerprint let a double click or a retried
// request return the first invoice rather than a second one.
//
// `sources` is what turns the same call into a Job handoff: present, the route runs the command that creates
// the draft and claims that work together; absent, it stays the direct invoice it has always been. The cap
// matches the 100 sources one invoice can claim, so an oversized selection is refused before it reaches the
// database.
export const createInvoiceSchema = z
	.object({
		client_id: z.string().uuid('Choose a client to continue.'),
		sources: z
			.array(invoiceSourceSchema)
			.max(100, 'An invoice can cover up to 100 pieces of work at once.')
			.optional(),
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

// Entering, saving or clearing the draft's contract disclaimer. A blank string clears it, so the field is
// optional rather than a min-length string — the same shape the quote disclaimer uses.
export const updateInvoiceContractDisclaimerSchema = z.object({
	expected_revision: z.number().int().min(0),
	contract_disclaimer: z
		.string()
		.trim()
		.max(5000, 'The contract disclaimer is too long. Keep it under 5000 characters.')
		.nullish()
		.transform((value) => value || null)
});

export type UpdateInvoiceContractDisclaimerInput = z.infer<
	typeof updateInvoiceContractDisclaimerSchema
>;

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

// Sending the invoice by email. The idempotency key makes a double click queue one email, not two; the link
// and recipient are decided in the database, not the browser.
export const invoiceEmailSchema = z.strictObject({
	idempotency_key: z.string().uuid('Start a new email attempt and try again.')
});

// Sending a payment receipt by email. Same shape as the invoice email: one key per send attempt, so a double
// click queues one receipt and a deliberate resend (a fresh key) sends again. The recipient, link and
// receipt contents are all decided in the database.
export const paymentReceiptEmailSchema = z.strictObject({
	idempotency_key: z.string().uuid('Start a new receipt attempt and try again.')
});

// The six manual methods the contract names — none of them processes a payment; each just acknowledges money
// received elsewhere. Same order and spelling as the database's own check constraint.
export const INVOICE_PAYMENT_METHODS = [
	'other',
	'bank_transfer',
	'cash',
	'check',
	'card_external',
	'paypal'
] as const;
export type InvoicePaymentMethod = (typeof INVOICE_PAYMENT_METHODS)[number];

// Collecting payment against the one invoice on screen. `amount_minor` is capped against what the bill still
// owes inside record_client_payment itself (private.apply_invoice_allocation) — restating that cap here would
// only be able to disagree with the database's own arithmetic, so it isn't repeated. Spreading one payment
// across several of a client's open invoices is a later, explicitly deferred screen; this shape carries only
// what a single-invoice collection needs.
export const recordInvoicePaymentSchema = z.object({
	// The browser already has this from the detail read it is acting on; record_client_payment re-checks the
	// invoice actually belongs to this client before it touches any money, so a tampered value only ever
	// fails closed as "that client could not be found," never a cross-tenant write.
	client_id: z.string().uuid(),
	amount_minor: z
		.number()
		.int()
		.min(1, 'Enter how much was paid.')
		.max(MINOR_UNIT_MAX, 'That amount is too large.'),
	method: z.enum(INVOICE_PAYMENT_METHODS, { message: 'Choose how this payment was received.' }),
	payment_date: z.string().regex(ISO_DATE, 'Pick a valid payment date.'),
	reference: z
		.string()
		.trim()
		.max(200, 'Keep the reference under 200 characters.')
		.nullish()
		.transform((value) => value || null),
	note: z
		.string()
		.trim()
		.max(2000, 'Keep the note under 2000 characters.')
		.nullish()
		.transform((value) => value || null),
	idempotency_key: z.string().uuid('Start a new action and try again.'),
	request_hash: z.string().trim().min(1, 'Reload and try again.').max(200, 'Reload and try again.')
});

export type RecordInvoicePaymentInput = z.infer<typeof recordInvoicePaymentSchema>;

// Copying the customer link takes no body: which invoice is in the URL, and the recipient is the client's own
// email. Strict so an unexpected field is refused rather than dropped.
export const issueInvoiceAccessLinkSchema = z.strictObject({});

// Invoices Part 7b: the five close/reopen transitions for an issued bill, each mapping 1:1 to a command built
// and pgTAP-tested in Part 3b (void_invoice, write_off_invoice, restore_invoice_from_write_off,
// mark_invoice_received, reopen_invoice). One discriminated shape because a single `/lifecycle` route runs all
// five — from the office's point of view this is one operation. None takes a revision; each command re-locks
// the row and leans on the idempotency key, so a double-press replays rather than erroring. The commands
// re-check every guard themselves (D2 among them — void refuses while ordinary payments are still applied), so
// this schema only shapes the request.
export { INVOICE_VOID_REASONS } from '$lib/invoices/lifecycle';
export type { InvoiceVoidReason } from '$lib/invoices/lifecycle';

import { INVOICE_VOID_REASONS } from '$lib/invoices/lifecycle';

const lifecycleRetry = {
	idempotency_key: z.string().uuid('Start a new action and try again.'),
	request_hash: z.string().trim().min(1, 'Reload and try again.').max(200, 'Reload and try again.')
};

// Void keeps an optional free-text note alongside its picked reason; write-off keeps only a note.
const lifecycleNote = z
	.string()
	.trim()
	.max(2000, 'Keep the note under 2000 characters.')
	.nullish()
	.transform((value) => value || null);

// Restore, mark-received and reopen each record why in a few words — required, so the history reads.
const lifecycleReason = z
	.string()
	.trim()
	.min(1, 'Say why in a few words.')
	.max(2000, 'Keep the reason under 2000 characters.');

export const invoiceLifecycleSchema = z.discriminatedUnion('action', [
	z.object({
		action: z.literal('void'),
		reason: z.enum(INVOICE_VOID_REASONS, { message: 'Pick a reason for voiding this invoice.' }),
		note: lifecycleNote,
		...lifecycleRetry
	}),
	z.object({ action: z.literal('write_off'), note: lifecycleNote, ...lifecycleRetry }),
	z.object({ action: z.literal('restore_write_off'), reason: lifecycleReason, ...lifecycleRetry }),
	z.object({ action: z.literal('mark_received'), reason: lifecycleReason, ...lifecycleRetry }),
	z.object({ action: z.literal('reopen'), reason: lifecycleReason, ...lifecycleRetry })
]);

export type InvoiceLifecycleInput = z.infer<typeof invoiceLifecycleSchema>;
