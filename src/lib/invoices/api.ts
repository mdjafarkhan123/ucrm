import type { InvoiceDerivedStatus } from './statuses';

export type InvoiceSortKey = 'created' | 'number';

export type InvoiceListFilters = {
	search: string;
	statuses: InvoiceDerivedStatus[];
	/** ISO instants, already widened to cover the whole day the person picked. */
	created_from: string;
	created_to: string;
	sort: InvoiceSortKey;
	dir: 'asc' | 'desc';
};

export type InvoiceListItem = {
	id: string;
	invoice_number: number;
	subject: string;
	currency_code: string;
	issue_date: string;
	due_date: string;
	issued_at: string | null;
	created_at: string;
	/** A superseded bill: its correction or rebill is the active one. Shown as a quiet "Replaced" mark. */
	is_replaced: boolean;
	/** Worked out in the database, never in the browser. */
	derived_status: InvoiceDerivedStatus;
	client: { id: string; display_name: string | null; company_name: string | null } | null;
	/** Null when this person may not see money at all — the table shows a dash, never a wrong number. */
	total_minor: number | null;
	/** What is still owed on the bill. Null on the same money-visibility rule as total. */
	remaining_minor: number | null;
};

export type InvoiceListPage = {
	invoices: InvoiceListItem[];
	// Null means this was the last page. Keyset paging, so there is no page number to jump to.
	next_cursor: string | null;
	locale: string;
};

export type InvoiceStatusCounts = Record<InvoiceDerivedStatus, number>;

export const invoicesListKey = (filters: InvoiceListFilters) =>
	['invoices', 'list', filters] as const;
export const invoiceCountsKey = ['invoices', 'counts'] as const;

type InvoiceReadError = Error;

async function readOrThrow<T>(response: Response, fallback: string): Promise<T> {
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw new Error(result.error ?? fallback) as InvoiceReadError;
	}
	return response.json();
}

export async function fetchInvoices(
	filters: InvoiceListFilters,
	cursor?: string
): Promise<InvoiceListPage> {
	const params = new URLSearchParams();
	if (filters.search) params.set('search', filters.search);
	// One comma-joined value, which is what the list route splits on.
	if (filters.statuses.length > 0) params.set('status', filters.statuses.join(','));
	if (filters.created_from) params.set('created_from', filters.created_from);
	if (filters.created_to) params.set('created_to', filters.created_to);
	if (filters.sort !== 'created') params.set('sort', filters.sort);
	if (filters.dir !== 'desc') params.set('dir', filters.dir);
	if (cursor) params.set('cursor', cursor);

	const response = await fetch(`/api/invoices?${params.toString()}`);
	return readOrThrow<InvoiceListPage>(response, 'Invoices could not be loaded.');
}

export type InvoiceOverview = {
	counts: InvoiceStatusCounts;
	currency_code: string;
	locale: string;
};

export async function fetchInvoiceOverview(): Promise<InvoiceOverview> {
	const response = await fetch('/api/invoices/counts');
	return readOrThrow<InvoiceOverview>(response, 'The overview could not be loaded.');
}
