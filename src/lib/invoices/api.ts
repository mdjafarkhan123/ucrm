import type { InvoiceDerivedStatus } from './statuses';
import type { InvoicePaymentMethod } from './payment-methods';
import type { InvoiceVoidReason } from './lifecycle';
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

// --- The ready-to-bill queue ------------------------------------------------------------------------------

// One job that owes an invoice today. `unit_kind` says what shape the waiting work is — the whole job, a
// number of completed visits, or a number of billing periods — and `uninvoiced_minor` is what those units
// come to. Both are worked out by the database from the same three rules the job's own billing cards use.
export type ReadyToBillJob = {
	job_id: string;
	job_number: number;
	title: string;
	job_type: string;
	price_basis: string;
	billing_timing: string;
	currency_code: string;
	oldest_due_on: string;
	due_reminder_count: number;
	unit_kind: string;
	unit_count: number;
	uninvoiced_minor: number;
	client: { id: string; display_name: string | null; company_name: string | null } | null;
	property: { label: string | null; address_line1: string | null; city: string | null };
};

export type ReadyToBillPage = {
	jobs: ReadyToBillJob[];
	next_cursor: string | null;
	timezone: string;
	locale: string;
};

// Both sit under the same `['invoices', 'ready-to-bill']` prefix so one invalidation after billing clears
// them together. The search term is fenced behind its own `list` segment: without it, searching for the word
// "count" would land on the count query's key and hand the table a number instead of a page.
export const readyToBillKey = (search: string) =>
	['invoices', 'ready-to-bill', 'list', search] as const;
export const readyToBillCountKey = ['invoices', 'ready-to-bill', 'count'] as const;

export async function fetchReadyToBill(search: string, cursor?: string): Promise<ReadyToBillPage> {
	const params = new URLSearchParams();
	if (search) params.set('search', search);
	if (cursor) params.set('cursor', cursor);

	const response = await fetch(`/api/invoices/ready-to-bill?${params.toString()}`);
	return readOrThrow<ReadyToBillPage>(response, 'The ready-to-bill list could not be loaded.');
}

export async function fetchReadyToBillCount(): Promise<number> {
	const response = await fetch('/api/invoices/ready-to-bill/count');
	return readOrThrow<{ count: number }>(response, 'That count could not be loaded.').then(
		(body) => body.count
	);
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

// One piece of billable work a new invoice claims. Sending any of these turns the save into a Job handoff:
// the draft and its claims are written together, so the bill can never exist without owning its work.
export type InvoiceSourceInput = {
	kind: 'job_total' | 'visit' | 'reminder_period' | 'installment';
	job_id: string;
	visit_id?: string | null;
	reminder_id?: string | null;
	installment_number?: number | null;
	service_property_index?: number | null;
};

export type CreateInvoicePayload = {
	client_id: string;
	subject: string;
	lines: InvoiceLineInput[];
	service_property_ids: string[];
	// Absent on a direct invoice, which has no job behind it.
	sources?: InvoiceSourceInput[];
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

// --- Billing a page of the queue at once (Part 8a) --------------------------------------------------------

export type BatchInvoicePayload = {
	job_ids: string[];
	/** Unfinished visits the contractor ticked. Each one is completed by the same save that bills it. */
	complete_visit_ids: string[];
	idempotency_key: string;
	request_hash: string;
};

export type BatchInvoiceResult = {
	applied?: boolean;
	invoice_count: number;
	job_count: number;
	visits_completed: number;
	invoices: {
		invoice_id: string;
		invoice_number: number;
		client_id: string;
		job_count: number;
		claimed_count: number;
	}[];
};

export async function createInvoicesInBatch(
	payload: BatchInvoicePayload
): Promise<BatchInvoiceResult> {
	const response = await fetch('/api/invoices/batch', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(payload)
	});
	return readOrThrow<BatchInvoiceResult>(response, 'Those invoices could not be created.');
}

// --- Batch deliver (Part 8b) ------------------------------------------------------------------------------

// One invoice a person may send in a batch: sendable (draft, awaiting payment, or past due), with the three
// facts the picker needs — the draft's `revision` (passed back to issue it on send), whether the client has an
// email at all (`has_email`, so "no email" is flagged before submit), and when it last went out
// (`last_sent_at`, so a previously-sent bill only ever re-sends on purpose). Carries no money.
export type DeliverableInvoice = {
	id: string;
	invoice_number: number;
	subject: string;
	currency_code: string;
	due_date: string;
	issued_at: string | null;
	derived_status: InvoiceDerivedStatus;
	revision: number;
	has_email: boolean;
	last_sent_at: string | null;
	client: { id: string; display_name: string | null; company_name: string | null } | null;
};

export type DeliverableInvoicesPage = {
	invoices: DeliverableInvoice[];
	next_cursor: string | null;
	timezone: string;
	locale: string;
};

export const deliverableInvoicesKey = ['invoices', 'deliverable', 'list'] as const;

export async function fetchDeliverableInvoices(cursor?: string): Promise<DeliverableInvoicesPage> {
	const params = new URLSearchParams();
	if (cursor) params.set('cursor', cursor);
	const query = params.toString();
	const response = await fetch(`/api/invoices/deliverable${query ? `?${query}` : ''}`);
	return readOrThrow<DeliverableInvoicesPage>(
		response,
		'The invoices you can send could not be loaded.'
	);
}

// One invoice in a send batch: which invoice, the revision the browser last read (used only to issue a draft),
// and a stable per-invoice key. The SAME key is resent when retrying — including after an uncertain response —
// so a retry returns the first result rather than sending twice; a deliberate fresh send uses new keys.
export type BatchDeliverItem = {
	invoice_id: string;
	expected_revision: number;
	idempotency_key: string;
};

// What became of each invoice. "queued" means accepted into the outbox (the sent/failed delivery fact is the
// worker's, shown on the invoice afterward); "rate_limited" carries the limiter's real retry delay and stops
// the batch; "skipped" is an invoice left untouched after that stop; "failed" carries a reason to show.
export type BatchDeliverOutcome =
	| { invoice_id: string; outcome: 'queued'; intent_id: string; status: string }
	| { invoice_id: string; outcome: 'rate_limited'; retry_after_seconds: number }
	| { invoice_id: string; outcome: 'skipped' }
	| { invoice_id: string; outcome: 'failed'; reason: string };

export type BatchDeliverResult = {
	results: BatchDeliverOutcome[];
	summary: { total: number; queued: number; failed: number; rate_limited: number; skipped: number };
};

export async function deliverInvoicesInBatch(
	invoices: BatchDeliverItem[]
): Promise<BatchDeliverResult> {
	const response = await fetch('/api/invoices/batch/deliver', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ invoices })
	});
	return readOrThrow<BatchDeliverResult>(response, 'Those invoices could not be sent.');
}

// --- What work is waiting to be billed --------------------------------------------------------------------

// One row of the "select work to invoice" picker: a job of this client that no invoice has claimed yet.
export type BillableWorkItem = {
	job_id: string;
	job_number: number;
	title: string;
	job_type: 'one_off' | 'recurring';
	created_at: string;
	currency_code: string;
	derived_status: string;
	property_id: string | null;
	property_label: string | null;
	property_address_line1: string | null;
	property_city: string | null;
	property_state_region: string | null;
	property_postal_code: string | null;
	subtotal_minor: number;
	uninvoiced_minor: number;
	total_minor: number;
	line_count: number;
	last_visit_date: string | null;
	visit_count: number;
	completed_visit_count: number;
	due_reminder_id: string | null;
};

export const billableWorkKey = (clientId: string) =>
	['invoices', 'billable-work', clientId] as const;

export async function fetchBillableWork(clientId: string): Promise<BillableWorkItem[]> {
	const response = await fetch(
		`/api/invoices/billable-work?client_id=${encodeURIComponent(clientId)}`
	);
	const body = await readOrThrow<{ work: BillableWorkItem[] }>(
		response,
		'That work could not be loaded.'
	);
	return body.work;
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

// One entry in the bill's money history: an application or an unapplication, from a manual receipt or a
// reused quote deposit. Null on the same invoices.view_price gate as `money` — a reader without price access
// never sees an amount, not even inside a history line.
export type InvoicePaymentHistoryEntry = {
	id: string;
	/** The recorded payment this row came from, so the row can link to its screen. Null on a deposit row —
	 *  a quote deposit is not a payment record and has no screen of its own. */
	payment_event_id: string | null;
	entry_type: 'applied' | 'unapplied';
	amount_minor: number;
	created_at: string;
	source: 'payment' | 'deposit';
	method: InvoicePaymentMethod | null;
	payment_date: string | null;
	reference: string | null;
	note: string | null;
	reason: string | null;
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
		write_off_note: string | null;
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
	payment_history: InvoicePaymentHistoryEntry[] | null;
	lines: InvoiceLineItem[];
	delivery: InvoiceDelivery;
	client_balance: InvoiceClientBalance | null;
	locale: string;
	can_edit: boolean;
	can_send: boolean;
	can_delete: boolean;
	can_record_payment: boolean;
	can_void: boolean;
	can_bad_debt: boolean;
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

// --- Collecting payment (single invoice) ------------------------------------------------------------------

export type RecordInvoicePaymentInput = {
	client_id: string;
	amount_minor: number;
	method: InvoicePaymentMethod;
	payment_date: string;
	reference: string | null;
	note: string | null;
	idempotency_key: string;
	request_hash: string;
};

export type RecordInvoicePaymentResult = {
	payment_event_id: string;
	client_id: string;
	amount_minor: number;
	currency_code: string;
	payment_date: string;
	allocated_minor: number;
	credit_minor: number;
	allocations: {
		allocation_id: string;
		invoice_id: string;
		invoice_number: number;
		amount_minor: number;
	}[];
};

// Records money against this invoice's client and applies it to this one bill, in one call. Spreading a
// payment across several of a client's open invoices is a later, deferred screen — see the invoices roadmap.
export async function recordInvoicePayment(
	id: string,
	input: RecordInvoicePaymentInput
): Promise<RecordInvoicePaymentResult> {
	const response = await fetch(`/api/invoices/${id}/payments`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	return readOrThrow<RecordInvoicePaymentResult>(response, 'That payment could not be recorded.');
}

export type QueuePaymentReceiptResult = {
	intent: { id: string; status: string; created_at: string };
};

// Emailing the customer their receipt for a payment already recorded. The email carries a link to the hosted
// receipt, not an attachment — we run no server PDF engine, and it is how we already send invoices. Keyed the
// same way as the invoice email, so a double click queues one receipt and a deliberate resend sends again.
export async function sendPaymentReceipt(
	paymentEventId: string,
	idempotencyKey: string
): Promise<QueuePaymentReceiptResult> {
	const response = await fetch(`/api/payments/${paymentEventId}/receipt`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ idempotency_key: idempotencyKey })
	});
	return readOrThrow<QueuePaymentReceiptResult>(response, 'The receipt email could not be queued.');
}

// --- One recorded payment (the detail screen) --------------------------------------------------------------

/** One bill this money was put against, or taken back off. `invoice_id` is null once that bill is gone —
 *  the allocation keeps its own copy of the number, so the row still reads right without a link to follow. */
export type PaymentAllocationEntry = {
	allocation_id: string;
	invoice_id: string | null;
	invoice_number: number;
	subject: string | null;
	entry_type: 'applied' | 'unapplied';
	amount_minor: number;
	created_at: string;
};

export type PaymentDetail = {
	payment: {
		id: string;
		amount_minor: number;
		currency_code: string;
		method: InvoicePaymentMethod;
		// A `date` column, so `YYYY-MM-DD` — never a timestamp.
		payment_date: string;
		reference: string | null;
		note: string | null;
		created_at: string;
	};
	client: {
		id: string;
		display_name: string | null;
		company_name: string | null;
		email: string | null;
	} | null;
	applied_to: PaymentAllocationEntry[];
	locale: string;
	can_send_receipt: boolean;
};

export const paymentDetailKey = (id: string) => ['payments', 'detail', id] as const;

// The read model refuses outright without money access, so there is no price-withheld shape to handle here:
// somebody who may not see amounts cannot open a payment at all.
export async function fetchPayment(id: string): Promise<PaymentDetail> {
	const response = await fetch(`/api/payments/${id}`);
	return readOrThrow<PaymentDetail>(response, 'That payment could not be loaded.');
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

// --- Lifecycle: void / bad debt / mark received (Part 7b) ------------------------------------------------

// One of the five close/reopen transitions on an issued bill. Each maps to a command re-checked and
// re-guarded in the database; the browser only says which one and carries the reason. `void` picks one of
// four internal reasons plus an optional note, `write_off` an optional note, the rest a required short reason.
export type InvoiceLifecycleAction =
	| { action: 'void'; reason: InvoiceVoidReason; note: string | null }
	| { action: 'write_off'; note: string | null }
	| { action: 'restore_write_off'; reason: string }
	| { action: 'mark_received'; reason: string }
	| { action: 'reopen'; reason: string };

export async function runInvoiceLifecycleAction(
	id: string,
	action: InvoiceLifecycleAction,
	idempotencyKey: string,
	requestHash: string
): Promise<void> {
	const response = await fetch(`/api/invoices/${id}/lifecycle`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			...action,
			idempotency_key: idempotencyKey,
			request_hash: requestHash
		})
	});
	await readOrThrow<unknown>(response, 'That change could not be saved.');
}
