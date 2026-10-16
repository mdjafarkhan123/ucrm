// What Home asks the server for beyond the overviews the list pages already share (jobs, quotes, requests and
// invoices counts). Each read is its own query, so one card failing never blocks the rest of Home.

import type { DayRange } from '$lib/home/money';
import type { InvoiceListItem } from '$lib/invoices/api';

async function readOrThrow<T>(response: Response, fallback: string): Promise<T> {
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw new Error(result.error ?? fallback);
	}
	return response.json();
}

export type MoneyOwed = {
	outstanding_minor: number;
	not_due_minor: number;
	overdue_1_30_minor: number;
	overdue_31_60_minor: number;
	overdue_61_90_minor: number;
	overdue_91_plus_minor: number;
	client_count: number;
	open_invoice_count: number;
};

export const moneyOwedKey = (asOf: string) => ['home', 'money-owed', asOf] as const;

/** What clients owe as of one day, split by how late. Needs invoice price access. */
export async function fetchMoneyOwed(asOf: string): Promise<MoneyOwed> {
	const response = await fetch(`/api/reports/financial/client-aging?as_of=${asOf}&limit=1`);
	const result = await readOrThrow<{ summary: MoneyOwed }>(
		response,
		'Money owed could not be loaded.'
	);
	return result.summary;
}

export const pastDueInvoicesKey = ['home', 'past-due-invoices'] as const;

/** The oldest past-due invoices, from which Home names the three that are latest. The list sorts by creation,
 * so the first page of the oldest-created is the nearest thing to "latest" the list can serve. */
export async function fetchPastDueInvoices(): Promise<InvoiceListItem[]> {
	const response = await fetch('/api/invoices?status=past_due&sort=created&dir=asc&limit=50');
	const result = await readOrThrow<{ invoices: InvoiceListItem[] }>(
		response,
		'Past-due invoices could not be loaded.'
	);
	return result.invoices;
}

export const invoicedKey = (range: DayRange) => ['home', 'invoiced', range] as const;
export const collectedKey = (range: DayRange) => ['home', 'collected', range] as const;

/** Billed sales before tax in a range (the Invoiced figure of the financial contract). */
export async function fetchInvoiced(range: DayRange): Promise<number> {
	const response = await fetch(
		`/api/reports/financial/invoice-sales?from=${range.from}&to=${range.to}&limit=1`
	);
	const result = await readOrThrow<{ summary: { net_sales_minor: number } }>(
		response,
		'Invoiced sales could not be loaded.'
	);
	return Number(result.summary.net_sales_minor);
}

/** Cash received less refunds in a range (the Collected figure of the financial contract). */
export async function fetchCollected(range: DayRange): Promise<number> {
	const response = await fetch(
		`/api/reports/financial/payment-events?from=${range.from}&to=${range.to}&limit=1`
	);
	const result = await readOrThrow<{ summary: { cash_effect_minor: number } }>(
		response,
		'Collected money could not be loaded.'
	);
	return Number(result.summary.cash_effect_minor);
}
