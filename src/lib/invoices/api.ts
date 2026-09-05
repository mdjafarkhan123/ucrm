import type { InvoiceDerivedStatus } from './statuses';
import type { QuoteDiscountType, QuoteTaxSource } from '$lib/quotes/api';

export type InvoiceWriteError = Error & {
	fieldErrors?: Record<string, string>;
	reason?: string;
};

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

async function readOrThrow<T>(response: Response, fallback: string): Promise<T> {
	if (!response.ok) {
		const result = await response
			.json()
			.catch(
				() => ({}) as { error?: string; field_errors?: Record<string, string>; reason?: string }
			);
		const error = new Error(result.error ?? fallback) as InvoiceWriteError;
		error.fieldErrors = result.field_errors ?? {};
		error.reason = result.reason;
		throw error;
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

// --- Payment terms (for the form) -------------------------------------------------------------------------

// One of the organization's named payment terms, oldest position first. The form offers these plus "Client's
// default" (send nothing and the command resolves the client/account default) and "Custom date".
export type InvoicePaymentTerm = {
	id: string;
	name: string;
	rule: string;
	net_days: number | null;
	is_protected: boolean;
};

export const invoicePaymentTermsKey = ['invoices', 'payment-terms'] as const;

export async function fetchInvoicePaymentTerms(): Promise<InvoicePaymentTerm[]> {
	const response = await fetch('/api/invoices/payment-terms');
	return readOrThrow<{ terms: InvoicePaymentTerm[] }>(
		response,
		'Those payment terms could not be loaded.'
	).then((body) => body.terms);
}

// --- Creating a draft invoice -----------------------------------------------------------------------------

// One priced invoice line, in the order the editor lists them. Position is set from the array index at send
// time, so the browser never keeps it in sync while lines are added or removed. An invoice line carries no
// internal cost — only what the customer is billed.
export type InvoiceLineInput = {
	position: number;
	category: 'product' | 'service';
	source_catalog_item_id: string | null;
	name: string;
	description: string | null;
	unit_label: string | null;
	quantity: number;
	unit_price_minor: number;
	is_taxable: boolean;
	service_date?: string | null;
};

export type CreateInvoicePayload = {
	client_id: string;
	subject: string;
	lines: InvoiceLineInput[];
	service_property_ids: string[];
	issue_date: string | null;
	// One of these two, never both. Null term means "let the command resolve the client/account default".
	payment_term_id: string | null;
	custom_due_date: string | null;
	// A stable key for one save intent, so a double click or a retry gets the first invoice back. The
	// fingerprint travels with it: the same key carrying different details is a conflict, not a replay.
	idempotency_key: string;
	request_hash: string;
};

export type CreateInvoiceResult = {
	applied?: boolean;
	invoice_id: string;
	invoice_number: number;
	revision: number;
	issue_date: string;
	due_date: string;
	currency_code: string;
	line_count: number;
};

export async function createInvoice(payload: CreateInvoicePayload): Promise<CreateInvoiceResult> {
	const response = await fetch('/api/invoices', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(payload)
	});
	return readOrThrow<CreateInvoiceResult>(response, 'That invoice could not be saved.');
}

// --- Reading one invoice ----------------------------------------------------------------------------------

// One line of the frozen document. Prices are null for a reader without invoices.view_price.
export type InvoiceLineItem = {
	id: string;
	position: number;
	line_kind: 'priced' | 'text' | 'heading';
	category: 'product' | 'service' | null;
	name: string;
	description: string | null;
	unit_label: string | null;
	quantity: number | null;
	is_taxable: boolean;
	service_date: string | null;
	unit_price_minor: number | null;
	line_total_minor: number | null;
};

// The invoice's money, gated. Null for a reader without invoices.view_price.
export type InvoiceMoney = {
	subtotal_minor: number;
	discount_minor: number;
	discount_name: string | null;
	discount_type: QuoteDiscountType | null;
	discount_value: number | null;
	tax_minor: number;
	tax_source: string;
	tax_name: string | null;
	tax_rate_id: string | null;
	tax_rate_basis_points: number;
	total_minor: number;
	allocated_minor: number;
	remaining_minor: number;
};

// The client's whole-account balance across all their bills, gated the same way. Null when the reader may not
// see money or the invoice has no client.
export type InvoiceClientBalance = {
	currency_code: string;
	outstanding_minor: number;
	available_credit_minor: number;
	account_balance_minor: number;
};

// A frozen snapshot the issued document shows. Kept loose: it is display-only and the shapes come straight
// from the database's own jsonb, never edited in the browser.
export type InvoiceServiceProperty = Record<string, unknown>;

// What the office knows about getting the bill to the client: the last email queued for it, and whether the
// customer has opened the link. Worked out in the database, aggregated across links so a rotated link never
// loses the fact that an earlier one was already seen.
export type InvoiceDelivery = {
	last_sent: {
		sent_at: string;
		status: string;
		recipient_email: string;
	} | null;
	views: {
		first_viewed_at: string | null;
		last_viewed_at: string | null;
		view_count: number;
	};
};

export type InvoiceDetail = {
	invoice: {
		id: string;
		invoice_number: number;
		revision: number;
		subject: string;
		currency_code: string;
		issue_date: string;
		due_date: string;
		due_date_source: string;
		payment_term_snapshot: Record<string, unknown> | null;
		contract_disclaimer: string | null;
		customer_snapshot: Record<string, unknown> | null;
		billing_address_snapshot: Record<string, unknown> | null;
		service_properties: InvoiceServiceProperty[];
		issued_at: string | null;
		issue_method: string | null;
		voided_at: string | null;
		void_reason: string | null;
		void_note: string | null;
		written_off_at: string | null;
		marked_received_at: string | null;
		recognized_at: string | null;
		replaced_at: string | null;
		replaced_by_invoice_id: string | null;
		predecessor_invoice_id: string | null;
		replacement_kind: string | null;
		is_replaced: boolean;
		derived_status: InvoiceDerivedStatus;
		client_id: string | null;
		created_at: string;
	};
	client: {
		id: string;
		display_name: string | null;
		company_name: string | null;
		email: string | null;
	} | null;
	money: InvoiceMoney | null;
	lines: InvoiceLineItem[];
	delivery: InvoiceDelivery;
	client_balance: InvoiceClientBalance | null;
	locale: string;
	can_edit: boolean;
	can_send: boolean;
	can_delete: boolean;
	can_see_price: boolean;
	can_manage_taxes: boolean;
};

export const invoiceDetailKey = (id: string) => ['invoices', 'detail', id] as const;

export async function fetchInvoice(id: string): Promise<InvoiceDetail> {
	const response = await fetch(`/api/invoices/${id}`);
	return readOrThrow<InvoiceDetail>(response, 'That invoice could not be loaded.');
}

// --- Editing a draft invoice ------------------------------------------------------------------------------

// Every one of these saves guards on the revision the browser last read and hands back the next one. None
// returns money: the page reloads the invoice for that, so amounts stay behind the database's price gate.
export type InvoiceRevisionResult = { revision: number };

export async function saveInvoiceDetails(
	id: string,
	expectedRevision: number,
	details: {
		subject: string;
		issue_date: string | null;
		payment_term_id: string | null;
		custom_due_date: string | null;
	}
): Promise<InvoiceRevisionResult & { issue_date: string; due_date: string }> {
	const response = await fetch(`/api/invoices/${id}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ expected_revision: expectedRevision, ...details })
	});
	return readOrThrow(response, 'Those changes could not be saved.');
}

export async function saveInvoiceLines(
	id: string,
	expectedRevision: number,
	lines: InvoiceLineInput[]
): Promise<InvoiceRevisionResult & { line_count: number }> {
	const response = await fetch(`/api/invoices/${id}/lines`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ expected_revision: expectedRevision, lines })
	});
	return readOrThrow(response, 'Those lines could not be saved.');
}

export async function saveInvoiceContractDisclaimer(
	id: string,
	expectedRevision: number,
	contractDisclaimer: string | null
): Promise<InvoiceRevisionResult> {
	const response = await fetch(`/api/invoices/${id}/disclaimer`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			expected_revision: expectedRevision,
			contract_disclaimer: contractDisclaimer
		})
	});
	return readOrThrow(response, 'That contract disclaimer could not be saved.');
}

// A null type removes the discount, which is why every field but the revision is optional.
export type InvoiceDiscountInput = {
	type: QuoteDiscountType | null;
	name: string | null;
	value: number | null;
};

export async function saveInvoiceDiscount(
	id: string,
	expectedRevision: number,
	discount: InvoiceDiscountInput
): Promise<InvoiceRevisionResult> {
	const response = await fetch(`/api/invoices/${id}/discount`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ expected_revision: expectedRevision, ...discount })
	});
	return readOrThrow(response, 'That discount could not be saved.');
}

export type InvoiceTaxInput = {
	source: QuoteTaxSource;
	rate_id?: string | null;
	custom_name?: string | null;
	custom_rate_basis_points?: number | null;
	save_as_reusable?: boolean;
};

export async function saveInvoiceTax(
	id: string,
	expectedRevision: number,
	tax: InvoiceTaxInput
): Promise<InvoiceRevisionResult> {
	const response = await fetch(`/api/invoices/${id}/tax`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ expected_revision: expectedRevision, ...tax })
	});
	return readOrThrow(response, 'That tax could not be saved.');
}

// --- Draft lifecycle --------------------------------------------------------------------------------------

export type IssueInvoiceResult = {
	applied?: boolean;
	invoice_id: string;
	invoice_number: number;
	revision: number;
	issued_at: string;
	issue_method: string;
	due_date: string;
};

// "Mark as Sent" issues the invoice with no transport. Emailing it (method 'sent') arrives with a later part.
export async function issueInvoice(
	id: string,
	expectedRevision: number,
	method: 'sent' | 'marked_sent',
	idempotencyKey: string,
	requestHash: string
): Promise<IssueInvoiceResult> {
	const response = await fetch(`/api/invoices/${id}/issue`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			expected_revision: expectedRevision,
			method,
			idempotency_key: idempotencyKey,
			request_hash: requestHash
		})
	});
	return readOrThrow<IssueInvoiceResult>(response, 'That invoice could not be issued.');
}

// --- Sending & the customer link --------------------------------------------------------------------------

export type QueueInvoiceEmailResult = {
	intent: { id: string; status: string; created_at: string };
};

// Emailing the invoice. The caller issues a draft first (issueInvoice, method 'sent'); this only delivers. The
// idempotency key makes a double click queue one email, not two.
export async function queueInvoiceEmail(
	id: string,
	idempotencyKey: string
): Promise<QueueInvoiceEmailResult> {
	const response = await fetch(`/api/invoices/${id}/email`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ idempotency_key: idempotencyKey })
	});
	return readOrThrow<QueueInvoiceEmailResult>(response, 'The invoice email could not be queued.');
}

export type InvoiceAccessLink = {
	invoice_id: string;
	invoice_access_link_id: string;
	recipient_name: string | null;
	recipient_email: string;
	issued_at: string;
	expires_at: string | null;
	url: string;
};

// The customer's own link, for "Copy customer link". The raw link comes back exactly once, in this response;
// asking again rotates the old one off, which is what staff mean by "send them the link again".
export async function issueInvoiceAccessLink(id: string): Promise<InvoiceAccessLink> {
	const response = await fetch(`/api/invoices/${id}/access-links`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: '{}'
	});
	return readOrThrow<InvoiceAccessLink>(response, 'That customer link could not be created.');
}

export type DeleteInvoiceResult = { applied?: boolean; invoice_id: string; invoice_number: number };

export async function deleteInvoice(
	id: string,
	expectedRevision: number,
	idempotencyKey: string,
	requestHash: string
): Promise<DeleteInvoiceResult> {
	const response = await fetch(`/api/invoices/${id}`, {
		method: 'DELETE',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			expected_revision: expectedRevision,
			idempotency_key: idempotencyKey,
			request_hash: requestHash
		})
	});
	return readOrThrow<DeleteInvoiceResult>(response, 'That invoice could not be deleted.');
}
