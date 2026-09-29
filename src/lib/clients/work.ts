import { fetchInvoices, type InvoiceListItem } from '$lib/invoices/api';
import { INVOICE_STATUS_LABELS, INVOICE_STATUS_TONES } from '$lib/invoices/statuses';
import { fetchJobs, type JobListItem } from '$lib/jobs/api';
import { JOB_DERIVED_STATUSES, JOB_STATUS_LABELS, JOB_STATUS_TONES } from '$lib/jobs/statuses';
import { fetchQuotes, type QuoteListItem } from '$lib/quotes/api';
import { QUOTE_STATUS_LABELS, QUOTE_STATUS_TONES, STORED_QUOTE_STATUSES } from '$lib/quotes/statuses';
import { fetchRequests, type RequestListItem } from '$lib/requests/api';
import { REQUEST_STATUS_LABELS, REQUEST_STATUS_TONES } from '$lib/requests/statuses';
import type { StatusTone } from '$lib/components/work/types';

// The client page's Work overview: one table of the client's own requests, quotes, jobs and invoices, the
// way Jobber's client page lists them (jobber-08-screen-patterns.md, "The client's linked-work table").
//
// It asks each work list's own route for this client's rows rather than keeping a second copy of their
// rules. Every status badge, every total and every money-visibility check is therefore exactly the one
// that record's own list shows, and a member who may not see a kind of work at all is refused by that
// route (403) — the kind is then left out rather than shown empty.

export const CLIENT_WORK_KINDS = ['request', 'quote', 'job', 'invoice'] as const;
export type ClientWorkKind = (typeof CLIENT_WORK_KINDS)[number];

export type ClientWorkItem = {
	kind: ClientWorkKind;
	id: string;
	/** "Quote #12" — the record type over its title, as the row reads. */
	label: string;
	title: string | null;
	address: string | null;
	created_at: string;
	status_label: string;
	status_tone: StatusTone;
	/** Null when there is no amount to show, or this person may not see it. */
	total_minor: number | null;
	currency_code: string | null;
};

export type ClientWorkPage = {
	items: ClientWorkItem[];
	next_cursor: string | null;
	locale: string | null;
};

/** The newest work of every kind this person may see, and which kinds those are. */
export type ClientRecentWork = {
	items: ClientWorkItem[];
	kinds: ClientWorkKind[];
	/** Some kind holds more than the recent view shows. */
	has_more: boolean;
	locale: string | null;
};

/** How many rows the mixed "All work" view shows before sending the reader to a kind of their choosing. */
export const CLIENT_RECENT_WORK_LIMIT = 10;
const KIND_PAGE_SIZE = 25;

export const clientWorkKey = (clientId: string) => ['clients', 'work', clientId] as const;
export const clientRecentWorkKey = (clientId: string) =>
	[...clientWorkKey(clientId), 'recent'] as const;
export const clientWorkKindKey = (clientId: string, kind: ClientWorkKind) =>
	[...clientWorkKey(clientId), kind] as const;

type Address = {
	label?: string | null;
	address_line1: string | null;
	city: string | null;
	state_region: string | null;
} | null;

function addressOf(property: Address) {
	if (!property) return null;
	return (
		[property.address_line1, property.city, property.state_region].filter(Boolean).join(', ') || null
	);
}

function fromRequest(row: RequestListItem): ClientWorkItem {
	return {
		kind: 'request',
		id: row.id,
		label: 'Request',
		title: row.title || row.service_type,
		address: addressOf(row.property),
		created_at: row.requested_at,
		status_label: REQUEST_STATUS_LABELS[row.status],
		status_tone: REQUEST_STATUS_TONES[row.status],
		total_minor: null,
		currency_code: null
	};
}

function fromQuote(row: QuoteListItem): ClientWorkItem {
	return {
		kind: 'quote',
		id: row.id,
		label: `Quote #${row.quote_number}`,
		title: row.title,
		// What the quote itself froze at send wins over the live property, as on the Quotes list.
		address: row.property_address ?? addressOf(row.property),
		created_at: row.created_at,
		status_label: QUOTE_STATUS_LABELS[row.status],
		status_tone: QUOTE_STATUS_TONES[row.status],
		total_minor: row.total_minor,
		currency_code: row.currency_code
	};
}

function fromJob(row: JobListItem): ClientWorkItem {
	return {
		kind: 'job',
		id: row.id,
		label: `Job #${row.job_number}`,
		title: row.title,
		address: addressOf(row.property),
		created_at: row.created_at,
		status_label: JOB_STATUS_LABELS[row.derived_status],
		status_tone: JOB_STATUS_TONES[row.derived_status],
		total_minor: row.total_minor,
		currency_code: row.currency_code
	};
}

function fromInvoice(row: InvoiceListItem): ClientWorkItem {
	return {
		kind: 'invoice',
		id: row.id,
		label: `Invoice #${row.invoice_number}`,
		title: row.subject,
		// A bill is addressed to the client, not to one property.
		address: null,
		created_at: row.created_at,
		status_label: INVOICE_STATUS_LABELS[row.derived_status],
		status_tone: INVOICE_STATUS_TONES[row.derived_status],
		total_minor: row.total_minor,
		currency_code: row.currency_code
	};
}

// The client's whole history, not only the open work each list opens on: every status is asked for where a
// list would otherwise hide its closed or archived rows.
export async function fetchClientWork(
	clientId: string,
	kind: ClientWorkKind,
	cursor?: string,
	limit = KIND_PAGE_SIZE
): Promise<ClientWorkPage> {
	const shared = { search: '', dir: 'desc' as const, client_id: clientId, limit };
	const range = { created_from: '', created_to: '' };
	switch (kind) {
		case 'request': {
			const page = await fetchRequests({ ...shared, statuses: [], sort: 'requested' }, cursor);
			return { items: page.requests.map(fromRequest), next_cursor: page.next_cursor, locale: null };
		}
		case 'quote': {
			const page = await fetchQuotes(
				{ ...shared, ...range, statuses: [...STORED_QUOTE_STATUSES], sort: 'created' },
				cursor
			);
			return { items: page.quotes.map(fromQuote), next_cursor: page.next_cursor, locale: page.locale };
		}
		case 'job': {
			const page = await fetchJobs(
				{ ...shared, ...range, statuses: [...JOB_DERIVED_STATUSES], types: [], sort: 'created' },
				cursor
			);
			return { items: page.jobs.map(fromJob), next_cursor: page.next_cursor, locale: page.locale };
		}
		case 'invoice': {
			const page = await fetchInvoices(
				{ ...shared, ...range, statuses: [], sort: 'created' },
				cursor
			);
			return {
				items: page.invoices.map(fromInvoice),
				next_cursor: page.next_cursor,
				locale: page.locale
			};
		}
	}
}

// The newest few of every kind, merged. Taking each kind's newest N and keeping the newest N of the union is
// exactly the newest N overall, so no kind's older rows are needed to get this view right.
export async function fetchClientRecentWork(clientId: string): Promise<ClientRecentWork> {
	const settled = await Promise.allSettled(
		CLIENT_WORK_KINDS.map((kind) => fetchClientWork(clientId, kind, undefined, CLIENT_RECENT_WORK_LIMIT))
	);

	const kinds: ClientWorkKind[] = [];
	const items: ClientWorkItem[] = [];
	let hasMore = false;
	let locale: string | null = null;
	settled.forEach((result, index) => {
		if (result.status === 'rejected') {
			// Not allowed to see this kind of work: leave it out. Anything else is a real failure.
			if ((result.reason as { status?: number }).status === 403) return;
			throw result.reason;
		}
		kinds.push(CLIENT_WORK_KINDS[index]);
		items.push(...result.value.items);
		if (result.value.next_cursor) hasMore = true;
		locale ??= result.value.locale;
	});

	// Compared as instants: the four routes do not all write their timestamps in the same text form.
	items.sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));
	if (items.length > CLIENT_RECENT_WORK_LIMIT) hasMore = true;
	return { items: items.slice(0, CLIENT_RECENT_WORK_LIMIT), kinds, has_more: hasMore, locale };
}
