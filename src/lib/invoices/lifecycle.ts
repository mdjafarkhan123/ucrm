// Invoices Part 7b: the vocabulary for the five close/reopen transitions on an issued bill. The browser reads
// these labels and the server Zod schema validates against the same list, the way statuses.ts already works.
// The transitions themselves are commands built and pgTAP-tested in Part 3b; this file adds no behaviour.

// Void's internal reason, exactly the four the behaviour contract names and the database's own check accepts.
export const INVOICE_VOID_REASONS = [
	'duplicate',
	'created_in_error',
	'client_request',
	'other'
] as const;

export type InvoiceVoidReason = (typeof INVOICE_VOID_REASONS)[number];

export const INVOICE_VOID_REASON_LABELS: Record<InvoiceVoidReason, string> = {
	duplicate: 'Duplicate',
	created_in_error: 'Created in error',
	client_request: 'Client request',
	other: 'Other'
};

export const INVOICE_VOID_REASON_OPTIONS = INVOICE_VOID_REASONS.map((value) => ({
	value,
	label: INVOICE_VOID_REASON_LABELS[value]
}));
