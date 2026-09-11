import type { InvoiceDocumentSnapshot } from './api';

// One changed field, already formatted for display. The database hands back two complete documents; naming
// what moved between them — and how to say it — is presentation, so it lives here rather than in SQL.
export type InvoiceDocumentChange = { label: string; before: string; after: string };

type Formatters = {
	formatMoney: (amountMinor: number) => string;
	formatDay: (value: string) => string;
};

const EMPTY = '—';

function text(value: string | null | undefined): string {
	return value && value.trim() ? value : EMPTY;
}

function termsLabel(document: InvoiceDocumentSnapshot): string {
	if (document.due_date_source === 'custom') return 'Custom due date';
	return document.payment_term_snapshot?.name ?? "Client's default terms";
}

function discountLabel(discount: InvoiceDocumentSnapshot['discount']): string {
	if (!discount.value) return 'None';
	const suffix = discount.type === 'percentage' ? '%' : '';
	return `${discount.name ?? 'Discount'} — ${discount.value}${suffix}`;
}

function taxLabel(tax: InvoiceDocumentSnapshot['tax']): string {
	if (!tax.name) return 'None';
	return `${tax.name} — ${(tax.rate_basis_points / 100).toFixed(2)}%`;
}

// A field-level before/after, the same shape Jobber's own Invoice History panel shows. Lines are compared as
// a whole rather than line-by-line: a bounded, staff-facing history read is not the place for a full nested
// diff, and "3 items → 4 items" already answers the question this panel exists to answer — did the bill
// change, and by roughly how much.
export function diffInvoiceDocument(
	before: InvoiceDocumentSnapshot,
	after: InvoiceDocumentSnapshot,
	{ formatMoney, formatDay }: Formatters
): InvoiceDocumentChange[] {
	const changes: InvoiceDocumentChange[] = [];
	const push = (label: string, beforeValue: string, afterValue: string) => {
		if (beforeValue !== afterValue) changes.push({ label, before: beforeValue, after: afterValue });
	};

	push('Subject', text(before.subject), text(after.subject));
	push('Invoice date', formatDay(before.issue_date), formatDay(after.issue_date));
	push('Due date', formatDay(before.due_date), formatDay(after.due_date));
	push('Payment terms', termsLabel(before), termsLabel(after));
	push('Discount', discountLabel(before.discount), discountLabel(after.discount));
	push('Tax', taxLabel(before.tax), taxLabel(after.tax));
	push('Total', formatMoney(before.totals.total_minor), formatMoney(after.totals.total_minor));

	if (JSON.stringify(before.lines) !== JSON.stringify(after.lines)) {
		const label = (count: number) => `${count} item${count === 1 ? '' : 's'}`;
		changes.push({
			label: 'Line items',
			before: label(before.lines.length),
			after: label(after.lines.length)
		});
	}

	return changes;
}
