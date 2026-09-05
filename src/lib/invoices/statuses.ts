import type { StatusTone } from '$lib/components/work/types';

// An invoice's status is never stored. private.invoice_live_status in the database works it out from the
// stored facts, the money applied to it, and the clock; a replaced bill keeps the label it was frozen with.
// This file only says what each of the six labels is called and which tone it wears. The database is the
// source; nothing here re-derives anything.
export const INVOICE_DERIVED_STATUSES = [
	'draft',
	'awaiting_payment',
	'past_due',
	'paid',
	'bad_debt',
	'voided'
] as const;

export type InvoiceDerivedStatus = (typeof INVOICE_DERIVED_STATUSES)[number];

export const INVOICE_STATUS_LABELS: Record<InvoiceDerivedStatus, string> = {
	draft: 'Draft',
	awaiting_payment: 'Awaiting payment',
	past_due: 'Past due',
	paid: 'Paid',
	bad_debt: 'Bad debt',
	voided: 'Voided'
};

export const INVOICE_STATUS_TONES: Record<InvoiceDerivedStatus, StatusTone> = {
	draft: 'inactive',
	awaiting_payment: 'informative',
	past_due: 'critical',
	paid: 'success',
	bad_debt: 'warning',
	voided: 'inactive'
};

// The four the office watches, in the order Jobber's own overview leads with: what is overdue, what is still
// owed, what is not sent yet, and what is settled. Bad debt and voided are terminal edge cases — filterable
// below, but not headline tiles.
export const INVOICE_OVERVIEW_STATUSES = ['past_due', 'awaiting_payment', 'draft', 'paid'] as const;

// Every status is a real, reachable label now that the ledger and lifecycle exist, so the Status filter
// offers all six.
export const INVOICE_FILTERABLE_STATUSES = INVOICE_DERIVED_STATUSES;
