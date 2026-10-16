import type { InvoiceDerivedStatus } from './statuses';

// The Invoices list's facts strip and the line under each row's number. The figures come from the database
// (`invoice_list_facts`, `invoice_list_views`); this module gives them a known shape and the short phrases
// the Pencil frame shows.

export type InvoiceListFacts = {
	/** Invoices paid in full in the past 30 days. */
	paid_count: number;
	/** Their average days from issue date to paid in full; null when none were paid. */
	average_days_to_paid: number | null;
	overdue_reminders_on: boolean;
	overdue_reminder_days_after_due: number | null;
};

export function readInvoiceListFacts(raw: unknown): InvoiceListFacts {
	const value = (raw ?? {}) as Record<string, unknown>;
	const average = value.average_days_to_paid;
	const days = value.overdue_reminder_days_after_due;
	return {
		paid_count: Number(value.paid_count) || 0,
		average_days_to_paid: average === null || average === undefined ? null : Number(average),
		overdue_reminders_on: value.overdue_reminders_on === true,
		overdue_reminder_days_after_due: days === null || days === undefined ? null : Number(days)
	};
}

function plural(count: number, word: string) {
	return `${count} ${word}${count === 1 ? '' : 's'}`;
}

/** "12 days" / "on average to get paid, past 30 days". */
export function averagePaidFact(facts: InvoiceListFacts): { value: string; label: string } {
	if (facts.average_days_to_paid === null)
		return { value: 'No invoices', label: 'paid in full in the past 30 days' };
	return {
		value: plural(facts.average_days_to_paid, 'day'),
		label: 'on average to get paid, past 30 days'
	};
}

/** "Overdue reminders on" / "1 day after the due date", or the off state. */
export function overdueReminderFact(facts: InvoiceListFacts): { value: string; label: string } {
	if (!facts.overdue_reminders_on) return { value: 'Overdue reminders off', label: '' };
	return {
		value: 'Overdue reminders on',
		label: `${plural(facts.overdue_reminder_days_after_due ?? 1, 'day')} after the due date`
	};
}

export type InvoiceRowNote = { text: string; unopened: boolean };

/** What follows the invoice number: "Part paid", "Viewed", "Viewed 3 times" or "Not opened yet". */
export function invoiceRowNote(invoice: {
	derived_status: InvoiceDerivedStatus;
	is_replaced: boolean;
	part_paid: boolean;
	/** Null when the bill was never emailed. */
	view_count: number | null;
}): InvoiceRowNote | null {
	if (invoice.part_paid) return { text: 'Part paid', unopened: false };
	// Only a bill still waiting on money says whether the client has seen it.
	if (invoice.is_replaced) return null;
	if (invoice.derived_status !== 'awaiting_payment' && invoice.derived_status !== 'past_due')
		return null;
	if (invoice.view_count === null) return null;
	if (invoice.view_count === 0) return { text: 'Not opened yet', unopened: true };
	if (invoice.view_count === 1) return { text: 'Viewed', unopened: false };
	return { text: `Viewed ${invoice.view_count} times`, unopened: false };
}
