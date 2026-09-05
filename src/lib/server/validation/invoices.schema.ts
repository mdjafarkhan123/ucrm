import { z } from 'zod';

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
