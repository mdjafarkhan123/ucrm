import type { StoredQuoteStatus } from './statuses';

export type PricingCategory = 'product' | 'service';

export type RequestPricingLine = {
	id: string;
	position: number;
	catalog_item_id: string | null;
	category: PricingCategory;
	is_labor: boolean;
	name: string;
	description: string | null;
	unit_label: string | null;
	quantity: number;
	unit_price_minor: number;
	unit_cost_minor: number;
	is_taxable: boolean;
	line_total_minor: number;
	line_cost_total_minor: number;
	image_attachment_id: string | null;
	line_kind?: QuoteLineKind;
	selection_kind?: QuoteSelectionKind;
	is_recommended?: boolean;
};

export type QuoteLineKind = 'priced' | 'text' | 'heading';
export type QuoteSelectionKind = 'required' | 'optional';

export type RequestPricing = {
	revision: number;
	subtotal_minor: number;
	editable: boolean;
	lines: RequestPricingLine[];
	currency_code: string;
	locale: string;
};

// What one row sends back on save. `id` never rides along — the whole set is replaced, so a browser-side
// key is all a draft row needs until it round-trips through the database again.
export type RequestPricingLineInput = {
	name: string;
	category: PricingCategory;
	is_labor: boolean;
	catalog_item_id: string | null;
	description?: string | null;
	unit_label?: string | null;
	quantity: number;
	unit_price_minor: number;
	unit_cost_minor: number;
	is_taxable?: boolean;
	image_attachment_id?: string | null;
	line_kind?: QuoteLineKind;
	selection_kind?: QuoteSelectionKind;
	is_recommended?: boolean;
};

export type RequestPricingWriteResult = {
	revision: number;
	line_count: number;
	subtotal_minor: number;
};

export type CatalogItem = {
	id: string;
	category: PricingCategory;
	name: string;
	description: string | null;
	unit_label: string | null;
	unit_price_minor: number;
	/** Missing when the person may not see internal cost — the API never sends the column. */
	unit_cost_minor?: number;
	is_taxable: boolean;
	is_labor: boolean;
	archived_at: string | null;
	updated_at: string;
	/** Bumped by the Settings Price Book commands; unused by the picker's own unprotected writes. */
	revision: number;
};

export type CatalogItemPage = {
	items: CatalogItem[];
	next_cursor: string | null;
	/** Whether this person may see internal cost at all, which an empty page cannot show on its own. */
	can_view_cost: boolean;
	/** Whether this person may open Settings → Price Book, independent of the broader `catalog.view` this
	 *  same list also serves for the picker. */
	can_manage: boolean;
};

export type ConvertRequestResult = {
	applied: boolean;
	quote_id: string;
	quote_number: string;
	quote_version_id: string;
	status: string;
	line_count: number;
	subtotal_minor: number;
};

export type QuoteWriteError = Error & {
	fieldErrors?: Record<string, string>;
	reason?: string;
};

async function readOrThrow<T>(response: Response, fallback: string): Promise<T> {
	if (!response.ok) {
		const result = await response
			.json()
			.catch(
				() => ({}) as { error?: string; field_errors?: Record<string, string>; reason?: string }
			);
		const error = new Error(result.error ?? fallback) as QuoteWriteError;
		error.fieldErrors = result.field_errors ?? {};
		error.reason = result.reason;
		throw error;
	}
	return response.json();
}

export const requestPricingKey = (requestId: string) => ['requests', 'pricing', requestId] as const;

export async function fetchRequestPricing(requestId: string): Promise<RequestPricing> {
	const response = await fetch(`/api/requests/${requestId}/pricing`);
	return readOrThrow<RequestPricing>(response, 'That pricing could not be loaded.');
}

export async function saveRequestPricing(
	requestId: string,
	expectedRevision: number,
	lines: RequestPricingLineInput[]
): Promise<RequestPricingWriteResult> {
	const response = await fetch(`/api/requests/${requestId}/pricing`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ expected_revision: expectedRevision, lines })
	});
	return readOrThrow<RequestPricingWriteResult>(response, 'That pricing could not be saved.');
}

export type CatalogItemFilter = 'exclude' | 'only';
export type CatalogSortKey = 'name' | 'price' | 'updated';

export type CatalogItemSearch = {
	search?: string;
	/** Products only, services only, or both when left out. */
	category?: PricingCategory;
	labor?: CatalogItemFilter;
	/** Settings → Price Book only; the picker never filters or sorts on these. */
	taxable?: CatalogItemFilter;
	sort?: CatalogSortKey;
	dir?: 'asc' | 'desc';
};

// The cursor stays out of the key: paging is one cache entry with its pages inside, not a new entry per
// page, so going back up the list never refetches what was already read.
export const catalogItemsKey = (query: CatalogItemSearch = {}) =>
	[
		'catalog-items',
		query.labor ?? 'all',
		query.category ?? 'all',
		query.search ?? '',
		query.taxable ?? 'all',
		query.sort ?? 'name',
		query.dir ?? 'asc'
	] as const;

export async function fetchCatalogItems(
	query: CatalogItemSearch = {},
	cursor?: string
): Promise<CatalogItemPage> {
	const params = new URLSearchParams();
	if (query.labor) params.set('labor', query.labor);
	if (query.category) params.set('category', query.category);
	if (query.search) params.set('search', query.search);
	if (query.taxable) params.set('taxable', query.taxable);
	if (query.sort) params.set('sort', query.sort);
	if (query.dir) params.set('dir', query.dir);
	if (cursor) params.set('cursor', cursor);
	const response = await fetch(`/api/catalog-items?${params.toString()}`);
	return readOrThrow<CatalogItemPage>(response, 'The price list could not be loaded.');
}

export type CatalogItemInput = {
	category: PricingCategory;
	name: string;
	description?: string | null;
	unit_label?: string | null;
	unit_price_minor: number;
	unit_cost_minor: number;
	is_taxable: boolean;
};

// Changing a saved item changes what the next line starts from. Nothing already written down moves —
// request lines and quote versions keep the copy they were given.
export async function updateCatalogItem(
	id: string,
	input: Partial<CatalogItemInput>
): Promise<CatalogItem> {
	const response = await fetch(`/api/catalog-items/${id}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	const result = await readOrThrow<{ item: CatalogItem }>(
		response,
		'That price list item could not be updated.'
	);
	return result.item;
}

export async function createCatalogItem(input: CatalogItemInput): Promise<CatalogItem> {
	const response = await fetch('/api/catalog-items', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	const result = await readOrThrow<{ item: CatalogItem }>(
		response,
		'That price list item could not be saved.'
	);
	return result.item;
}

export async function convertRequestToQuote(
	requestId: string,
	idempotencyKey: string,
	requestHash: string
): Promise<ConvertRequestResult> {
	const response = await fetch(`/api/requests/${requestId}/convert-to-quote`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ idempotency_key: idempotencyKey, request_hash: requestHash })
	});
	return readOrThrow<ConvertRequestResult>(response, 'This request could not become a quote.');
}

// --- The list page --------------------------------------------------------------------------------

export type QuoteSortKey = 'created' | 'number';

export type QuoteListFilters = {
	search: string;
	statuses: StoredQuoteStatus[];
	/** ISO instants, already widened to cover the whole day the person picked. */
	created_from: string;
	created_to: string;
	sort: QuoteSortKey;
	dir: 'asc' | 'desc';
};

export type QuoteListItem = {
	id: string;
	quote_number: number;
	title: string | null;
	status: StoredQuoteStatus;
	currency_code: string;
	created_at: string;
	from_request: boolean;
	client: { id: string; display_name: string; company_name: string | null } | null;
	property: {
		id: string;
		label: string | null;
		address_line1: string;
		city: string;
		state_region: string | null;
		postal_code: string | null;
	} | null;
	/** Null when this person may not see money at all — the table shows a dash, never a wrong number. */
	total_minor: number | null;
};

export type QuoteListPage = {
	quotes: QuoteListItem[];
	// Null means this was the last page. Keyset paging, so there is no page number to jump to.
	next_cursor: string | null;
	locale: string;
};

export type QuoteStatusCounts = Record<StoredQuoteStatus, number>;

export const quotesListKey = (filters: QuoteListFilters) => ['quotes', 'list', filters] as const;
export const quoteCountsKey = ['quotes', 'counts'] as const;

export async function fetchQuotes(
	filters: QuoteListFilters,
	cursor?: string
): Promise<QuoteListPage> {
	const params = new URLSearchParams();
	if (filters.search) params.set('search', filters.search);
	// One comma-joined value, which is what the list route splits on.
	if (filters.statuses.length > 0) params.set('status', filters.statuses.join(','));
	if (filters.created_from) params.set('created_from', filters.created_from);
	if (filters.created_to) params.set('created_to', filters.created_to);
	if (filters.sort !== 'created') params.set('sort', filters.sort);
	if (filters.dir !== 'desc') params.set('dir', filters.dir);
	if (cursor) params.set('cursor', cursor);

	const response = await fetch(`/api/quotes?${params.toString()}`);
	return readOrThrow<QuoteListPage>(response, 'Quotes could not be loaded.');
}

export type QuoteOverview = {
	counts: QuoteStatusCounts;
	/** The organization's money format, which the new-quote form needs before a quote exists. */
	currency_code: string;
	locale: string;
};

export async function fetchQuoteOverview(): Promise<QuoteOverview> {
	const response = await fetch('/api/quotes/counts');
	return readOrThrow<QuoteOverview>(response, 'The overview could not be loaded.');
}

// --- Creating and editing a quote ----------------------------------------------------------------

export type QuoteCreateInput = {
	client_id: string;
	property_id: string;
	title: string;
	contract_disclaimer?: string | null;
};

export type QuoteCreateResult = {
	quote_id: string;
	quote_number: number;
	quote_version_id: string;
	status: StoredQuoteStatus;
	/** The draft's revision, which the very next line save has to send back. */
	revision: number;
};

export async function createQuote(input: QuoteCreateInput): Promise<QuoteCreateResult> {
	const response = await fetch('/api/quotes', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	return readOrThrow<QuoteCreateResult>(response, 'That quote could not be saved.');
}

export const quoteLinesKey = (quoteId: string) => ['quotes', 'lines', quoteId] as const;

export type QuoteDetail = {
	quote: {
		id: string;
		quote_number: number;
		title: string | null;
		status: StoredQuoteStatus;
		currency_code: string;
		client_id: string;
		property_id: string;
		request_id: string | null;
		draft_version_id: string | null;
		current_published_version_id: string | null;
		archived_at: string | null;
		archive_reason: string | null;
		previous_status: StoredQuoteStatus | null;
		sent_at: string | null;
		decision: 'approved' | 'declined' | null;
		decided_at: string | null;
		decision_method: 'offline_verbal' | 'online' | 'in_person' | null;
		decision_note: string | null;
		created_at: string;
		updated_at: string;
		client: {
			id: string;
			display_name: string;
			company_name: string | null;
			email: string | null;
			phone: string | null;
		} | null;
		property: {
			id: string;
			label: string | null;
			address_line1: string;
			address_line2: string | null;
			city: string;
			state_region: string | null;
			postal_code: string | null;
			country: string;
		} | null;
	};
	version: {
		id: string;
		version_number: number;
		/** 'draft' while staff are working on it, 'published' once it has been frozen. */
		status: string;
		published_at: string | null;
		revision: number;
		contract_disclaimer: string | null;
		currency_code: string;
		client_display_name: string;
		organization_name: string;
		service_address_line1: string;
		service_address_line2: string | null;
		service_city: string;
		service_state_region: string | null;
		service_postal_code: string | null;
		service_country: string;
		created_at: string;
		introduction: string | null;
		client_message: string | null;
		show_quantities: boolean;
		show_unit_prices: boolean;
		show_line_totals: boolean;
		show_totals: boolean;
		discount_name: string | null;
		discount_type: QuoteDiscountType | null;
		/** Whole cents for a fixed discount, basis points for a percentage one. */
		discount_value: number | null;
		tax_source: QuoteTaxSource;
		tax_name: string | null;
		tax_rate_basis_points: number;
		tax_rate_id: string | null;
		deposit_type: QuoteDepositType | null;
		subtotal_minor?: number;
		discount_minor?: number;
		tax_minor?: number;
		total_minor?: number;
		/** What this version's deposit prices out to, live with the draft or frozen once sent. */
		deposit_required_minor?: number;
		/** Internal money. Present only for someone with `quotes.view_cost`. */
		cost_minor?: number;
		profit_minor?: number;
		margin_basis_points?: number | null;
	} | null;
	/** The number of the version standing behind this quote, or null while nothing is published. */
	published_version_number: number | null;
	lines: Array<
		Omit<
			RequestPricingLine,
			| 'catalog_item_id'
			| 'unit_price_minor'
			| 'unit_cost_minor'
			| 'line_total_minor'
			| 'line_cost_total_minor'
		> & {
			source_catalog_item_id: string | null;
			unit_price_minor?: number;
			unit_cost_minor?: number;
			line_total_minor?: number;
			line_cost_total_minor?: number;
		}
	>;
	version_attachments: QuoteVersionAttachment[];
	/** The signature on the answer that currently counts, if it was signed at all. */
	signature: QuoteSignature | null;
	/** The deposit installments for whichever version is on screen — draft while one is in progress. */
	deposit_schedule_items: QuoteDepositScheduleItem[];
	/** The receipt ledger for the currently published version only; empty until something is sent. */
	deposit_events: QuoteDepositEvent[];
	/** Approved, and no required deposit is still outstanding. Separate from approval itself — a required
	 * deposit never blocks the customer's decision, only whether the quote is ready to become a Job. */
	ready_for_job: boolean;
	can_see_price: boolean;
	can_see_cost: boolean;
	can_edit: boolean;
	can_send: boolean;
	/** Quote email additionally creates a customer conversation, so it needs both authorities. */
	can_send_email: boolean;
	can_record_decision: boolean;
	can_record_deposit: boolean;
	can_manage_taxes: boolean;
};

export const quoteDetailKey = (quoteId: string) => ['quotes', 'detail', quoteId] as const;

export async function fetchQuote(quoteId: string): Promise<QuoteDetail> {
	const response = await fetch(`/api/quotes/${quoteId}`);
	return readOrThrow<QuoteDetail>(response, 'That quote could not be loaded.');
}

export type QuoteDraftWriteResult = { revision: number; title: string };

export async function saveQuoteDraft(
	quoteId: string,
	expectedRevision: number,
	input: { title: string; contract_disclaimer: string | null }
): Promise<QuoteDraftWriteResult> {
	const response = await fetch(`/api/quotes/${quoteId}/draft`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ expected_revision: expectedRevision, ...input })
	});
	return readOrThrow<QuoteDraftWriteResult>(response, 'That quote could not be saved.');
}

export async function saveQuoteLines(
	quoteId: string,
	expectedRevision: number,
	lines: RequestPricingLineInput[]
): Promise<QuoteCommandResult> {
	const response = await fetch(`/api/quotes/${quoteId}/lines`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ expected_revision: expectedRevision, lines })
	});
	return readOrThrow<QuoteCommandResult>(response, 'Those lines could not be saved.');
}

export type QuoteTotals = {
	subtotal_minor: number;
	discount_minor: number;
	tax_minor: number;
	total_minor: number;
};

export type QuoteCommandResult = { revision: number; totals: QuoteTotals };

export async function previewQuoteTotals(
	quoteId: string,
	addonIds: string[]
): Promise<QuoteTotals> {
	const response = await fetch(`/api/quotes/${quoteId}/preview`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ addon_ids: addonIds })
	});
	return readOrThrow<QuoteTotals>(response, 'Those totals could not be previewed.');
}

export type QuoteDiscountType = 'fixed' | 'percentage';

/** One of the quote's own files, marked for the copy the customer reads. */
export type QuoteVersionAttachment = {
	id: string;
	attachment_id: string;
	position: number;
	customer_visible: boolean;
	display_name: string;
};

export type QuoteVersionAttachmentInput = {
	attachment_id: string;
	display_name: string;
	customer_visible: boolean;
};

// Everything below sends the revision the browser last read and gets back the new one plus the totals the
// database just worked out. Nothing here does arithmetic — the figures on screen are the ones that came back.
async function patchQuote<T = QuoteCommandResult>(
	quoteId: string,
	path: string,
	body: Record<string, unknown>,
	fallback: string
): Promise<T> {
	const response = await fetch(`/api/quotes/${quoteId}/${path}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	return readOrThrow<T>(response, fallback);
}

/** What publishing hands back. `already_published` is true when the click landed on a version that exists. */
export type QuotePublishResult = {
	quote_id: string;
	quote_version_id: string;
	version_number: number;
	sent_at: string | null;
	status: StoredQuoteStatus;
	already_published: boolean;
};

export async function publishQuote(
	quoteId: string,
	expectedRevision: number
): Promise<QuotePublishResult> {
	return postQuote(
		quoteId,
		'publish',
		{ expected_revision: expectedRevision },
		'This quote could not be sent.'
	);
}

/** Copies the published version into a fresh draft. The customer's document is never edited in place. */
export async function reviseQuote(quoteId: string): Promise<{ quote_version_id: string }> {
	return postQuote(quoteId, 'revise', {}, 'This quote could not be revised.');
}

/** A brand-new quote that starts full: same client/property/lines/sections, no lineage carried over. */
export async function createSimilarQuote(
	quoteId: string
): Promise<{ quote_id: string; quote_number: number }> {
	return postQuote(quoteId, 'similar', {}, 'This quote could not be copied.');
}

export type QuoteArchiveResult = { applied: boolean; status: StoredQuoteStatus };

export async function archiveQuote(
	quoteId: string,
	reason?: string | null
): Promise<QuoteArchiveResult> {
	return postQuote(
		quoteId,
		'archive',
		{ reason: reason ?? null },
		'This quote could not be archived.'
	);
}

export async function restoreQuote(quoteId: string): Promise<QuoteArchiveResult> {
	return postQuote(quoteId, 'restore', {}, 'This quote could not be restored.');
}

/** Only ever succeeds for an untouched, directly-created draft — the command refuses everything else. */
export async function deleteQuote(quoteId: string): Promise<{ quote_id: string }> {
	const response = await fetch(`/api/quotes/${quoteId}`, { method: 'DELETE' });
	return readOrThrow(response, 'This quote could not be deleted.');
}

export async function bulkArchiveQuotes(
	ids: string[]
): Promise<{ archived: number; skipped: number }> {
	const response = await fetch('/api/quotes/bulk-archive', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ ids })
	});
	return readOrThrow(response, 'Those quotes could not be archived.');
}

export type QuoteDecisionResult = {
	quote_id: string;
	status: StoredQuoteStatus;
	decision: 'approved' | 'declined' | null;
	decided_at: string | null;
	already_decided: boolean;
};

export type QuoteSignature = {
	quote_signature_id: string;
	signer_name: string;
	method: 'typed' | 'drawn' | 'in_person';
	signed_at: string;
	/** Whether there is a drawing to fetch. The object key itself never leaves the server. */
	has_image: boolean;
	version_number: number;
};

/** Where the drawn signature is streamed from. It needs a session and the permission to see the quote. */
export function quoteSignatureImageHref(quoteId: string, signatureId: string) {
	return `/api/quotes/${quoteId}/signature/${signatureId}/image`;
}

/**
 * Jobber's Collect Signature: the in-person close. Signing is what approves the quote, so this is an
 * approval with a different method rather than a separate act - and from a draft it publishes first.
 */
export async function collectQuoteSignature(
	quoteId: string,
	input: {
		name: string;
		method: 'typed' | 'in_person';
		image?: string | null;
		note?: string | null;
		expectedRevision?: number;
	}
): Promise<QuoteDecisionResult> {
	return postQuote(
		quoteId,
		'signature',
		{
			name: input.name,
			method: input.method,
			...(input.image ? { image: input.image } : {}),
			note: input.note ?? null,
			...(input.expectedRevision === undefined ? {} : { expected_revision: input.expectedRevision })
		},
		'That signature could not be recorded.'
	);
}

/** An answer the customer gave off the app. A draft is published first, so the answer has a document. */
export async function recordQuoteDecision(
	quoteId: string,
	input: { decision: 'approved' | 'declined'; note?: string | null; expectedRevision?: number }
): Promise<QuoteDecisionResult> {
	return postQuote(
		quoteId,
		'decision',
		{
			decision: input.decision,
			note: input.note ?? null,
			...(input.expectedRevision === undefined ? {} : { expected_revision: input.expectedRevision })
		},
		'That answer could not be recorded.'
	);
}

export type QuoteAccessLink = {
	quote_access_link_id: string;
	quote_version_id: string;
	version_number: number;
	recipient_name: string;
	recipient_email: string;
	issued_at: string;
	expires_at: string | null;
	url: string;
};

/**
 * Makes the customer's door and hands back the only copy of the key. The raw link is in this response
 * and nowhere else — it is not stored, not logged, and cannot be read back afterwards, so a staff member
 * who loses it makes a new one, which turns the old one off in the same breath.
 */
export async function issueQuoteAccessLink(quoteId: string): Promise<QuoteAccessLink> {
	return postQuote(quoteId, 'access-links', {}, 'That customer link could not be created.');
}

export type QuoteEmailIntent = {
	id: string;
	status: string;
	created_at: string;
};

/** The server re-resolves the published quote, recipient, sender, secure link, and allowance. */
export async function queueQuoteEmail(quoteId: string, idempotencyKey: string) {
	return postQuote<{ intent: QuoteEmailIntent }>(
		quoteId,
		'email',
		{ idempotency_key: idempotencyKey },
		'The quote email could not be queued.'
	);
}

async function postQuote<T>(
	quoteId: string,
	path: string,
	body: Record<string, unknown>,
	fallback: string
): Promise<T> {
	const response = await fetch(`/api/quotes/${quoteId}/${path}`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	return readOrThrow<T>(response, fallback);
}

export type QuoteDiscountInput = {
	name: string | null;
	type: QuoteDiscountType | null;
	/** Whole cents when the type is fixed, basis points when it is a percentage. */
	value: number | null;
};

/** Sending a null type is the Remove button: the name and the value go with it. */
export async function saveQuoteDiscount(
	quoteId: string,
	expectedRevision: number,
	input: QuoteDiscountInput
): Promise<QuoteCommandResult> {
	return patchQuote(
		quoteId,
		'discount',
		{ expected_revision: expectedRevision, ...input },
		'That discount could not be saved.'
	);
}

export type QuoteTaxSource =
	'not_configured' | 'business_default' | 'property_default' | 'saved_rate' | 'no_tax' | 'custom';

export type QuoteTaxInput = {
	source: Exclude<QuoteTaxSource, 'not_configured'>;
	rate_id: string | null;
	custom_name: string | null;
	custom_rate_basis_points: number | null;
	/** Only meaningful with `source: 'custom'`; the database refuses it from anyone but an owner/admin. */
	save_as_reusable: boolean;
};

/** Re-resolves the effective default, freezes one saved rate or a one-off custom rate, or says No tax. */
export async function saveQuoteTax(
	quoteId: string,
	expectedRevision: number,
	input: QuoteTaxInput
): Promise<QuoteCommandResult> {
	return patchQuote(
		quoteId,
		'tax',
		{ expected_revision: expectedRevision, ...input },
		'That tax could not be saved.'
	);
}

export type QuoteDepositType = 'deposit_only' | 'schedule';

/** One installment on a deposit-only or schedule deposit, priced by the database. */
export type QuoteDepositScheduleItem = {
	id: string;
	position: number;
	description: string;
	value_type: 'fixed' | 'percentage';
	/** Whole cents for a fixed installment, basis points for a percentage one. */
	value: number;
	is_deposit: boolean;
};

export type QuoteDepositMethod = 'cash' | 'check' | 'other';

/** One receipt or reversal on the immutable deposit ledger. A reversal names the receipt it corrects. */
export type QuoteDepositEvent = {
	id: string;
	quote_version_id: string;
	event_type: 'received' | 'reversed';
	amount_minor: number;
	method: QuoteDepositMethod;
	reference: string | null;
	note: string | null;
	reversed_event_id: string | null;
	created_at: string;
};

export type QuoteDepositScheduleItemInput = {
	description: string;
	type: 'fixed' | 'percentage';
	value: number;
};

/** Sending a null deposit type is the Remove button: every installment goes with it. */
export async function saveQuoteDeposit(
	quoteId: string,
	expectedRevision: number,
	input: { deposit_type: QuoteDepositType | null; items: QuoteDepositScheduleItemInput[] }
): Promise<QuoteCommandResult> {
	return patchQuote(
		quoteId,
		'deposit',
		{ expected_revision: expectedRevision, ...input },
		'That deposit could not be saved.'
	);
}

export type QuoteDepositEventResult = {
	applied: boolean;
	event_id: string;
	/** Present only when this call is the one that actually recorded the receipt, not a replay. */
	amount_minor?: number;
	quote_version_id?: string;
};

/** Recording money that changed hands off the app, against whichever version is currently published. */
export async function recordQuoteDepositEvent(
	quoteId: string,
	input: {
		idempotencyKey: string;
		method: QuoteDepositMethod;
		reference?: string | null;
		note?: string | null;
	}
): Promise<QuoteDepositEventResult> {
	return postQuote(
		quoteId,
		'deposit-events',
		{
			idempotency_key: input.idempotencyKey,
			method: input.method,
			reference: input.reference ?? null,
			note: input.note ?? null
		},
		'That deposit could not be recorded.'
	);
}

export type QuoteDepositReversalResult = { applied: boolean; event_id: string };

/** A correction, not an undo — the receipt stays exactly as recorded. */
export async function reverseQuoteDepositEvent(
	quoteId: string,
	eventId: string,
	input: { idempotencyKey: string; reason: string }
): Promise<QuoteDepositReversalResult> {
	return postQuote(
		quoteId,
		`deposit-events/${eventId}/reverse`,
		{ idempotency_key: input.idempotencyKey, reason: input.reason },
		'That deposit could not be reversed.'
	);
}

export type QuoteVisibility = {
	show_quantities: boolean;
	show_unit_prices: boolean;
	show_line_totals: boolean;
	show_totals: boolean;
};

export async function saveQuoteVisibility(
	quoteId: string,
	expectedRevision: number,
	input: QuoteVisibility
): Promise<QuoteCommandResult> {
	return patchQuote(
		quoteId,
		'visibility',
		{ expected_revision: expectedRevision, ...input },
		'Those client view settings could not be saved.'
	);
}

export async function saveQuoteCopy(
	quoteId: string,
	expectedRevision: number,
	input: { introduction: string | null; client_message: string | null }
): Promise<QuoteCommandResult> {
	return patchQuote(
		quoteId,
		'copy',
		{ expected_revision: expectedRevision, ...input },
		'That wording could not be saved.'
	);
}

/** Which of the quote's own files belong in the customer's copy. The files themselves are not touched. */
export async function saveQuoteVersionAttachments(
	quoteId: string,
	expectedRevision: number,
	attachments: QuoteVersionAttachmentInput[]
): Promise<QuoteCommandResult> {
	return patchQuote(
		quoteId,
		'attachments',
		{ expected_revision: expectedRevision, attachments },
		'Those files could not be saved.'
	);
}
