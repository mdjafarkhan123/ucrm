export type ClientSortKey = 'updated_at' | 'name' | 'status';

export type ClientListFilters = {
	search: string;
	status: 'lead' | 'customer' | 'archived' | '';
	tagId: string;
	sort: ClientSortKey;
	dir: 'asc' | 'desc';
};

export type ClientListItem = {
	id: string;
	display_name: string;
	company_name: string | null;
	client_type: string;
	lifecycle_status: string;
	lead_source: string | null;
	archived_at: string | null;
	updated_at: string;
	primary_property: {
		id: string;
		label: string;
		address_line1: string;
		city: string;
		state_region: string | null;
		postal_code: string | null;
	} | null;
	additional_property_count: number;
	email: string | null;
	phone: string | null;
	tags: { id: string; name: string; color: string | null }[];
};

export type ClientListPage = {
	clients: ClientListItem[];
	// Null means this was the last page. The list is keyset paginated, so there is no page number to
	// jump to — the cursor is the only way to ask for what comes next.
	next_cursor: string | null;
	/** Whether this member holds customers.archive, so the list can offer Archive and Restore. */
	can_archive: boolean;
	/** Whether this member holds customers.merge, so the list can offer Merge clients. */
	can_merge?: boolean;
};

export type ClientPreferences = {
	contact_policy: 'allow' | 'no_marketing' | 'do_not_disturb';
	quote_follow_ups: boolean;
	invoice_reminders: boolean;
	appointment_reminders: boolean;
	job_follow_ups: boolean;
	review_requests: boolean;
};

/**
 * Marketing-email consent for a client's email, read from the append-only evidence ledger (never from the
 * legacy preference flag). `state` is 'unknown' until an opt-in or opt-out is recorded; `source` and
 * `effective_at` are null until then.
 */
export type MarketingConsentState = {
	/** The email address consent is tracked against — the client's primary email. */
	email: string;
	/** The contact method a recorded event targets. */
	contact_method_id: string;
	state: 'opted_in' | 'opted_out' | 'unknown';
	source: 'public_form' | 'staff' | 'unsubscribe' | 'complaint' | null;
	effective_at: string | null;
};

export type ClientPropertyInput = {
	label?: string;
	address_line1: string;
	address_line2?: string;
	city: string;
	state_region?: string;
	postal_code?: string;
	country?: string;
	access_notes?: string;
	is_billing_address?: boolean;
	/** Null inherits the Business default tax; a saved rate's id pins this property to it. */
	tax_rate_id?: string | null;
};

export type ClientWriteValues = {
	client_type: 'person' | 'company';
	lifecycle_status: 'lead' | 'customer';
	first_name?: string;
	last_name?: string;
	company_name?: string;
	email?: string;
	billing_email?: string;
	phone?: string;
	lead_source?: string;
	initial_note?: string;
	property?: ClientPropertyInput;
	preferences: ClientPreferences;
	tag_ids: string[];
};

/**
 * The client fields a detail-page block can stage. Blocks edit into a draft of this shape and one save
 * writes them together, so lead source, tags, and properties are deliberately not part of it.
 */
export type ClientIdentityDraft = {
	client_type: 'person' | 'company';
	lifecycle_status: 'lead' | 'customer';
	first_name: string;
	last_name: string;
	company_name: string;
	email: string;
	billing_email: string;
	phone: string;
	preferences: ClientPreferences;
};

export type ClientProperty = ClientPropertyInput & {
	id: string;
	is_primary: boolean;
	is_billing_address: boolean;
};

export type ClientDetail = ClientWriteValues & {
	id: string;
	display_name: string;
	billing_email: string | null;
	created_at: string;
	converted_to_customer_at: string | null;
	archived_at: string | null;
	primary_property: ClientProperty | null;
	/** Every property this client has, primary first. The form uses primary_property; the detail page uses this. */
	properties: ClientProperty[];
	property_count: number;
	contact_methods: {
		id: string;
		kind: 'email' | 'phone';
		value: string;
		is_primary: boolean;
		is_billing_contact: boolean;
	}[];
	preferences:
		(ClientPreferences & { sms_opt_out_at: string | null; sms_opt_in_at: string | null }) | null;
	/**
	 * Marketing-email consent for the client's primary email. Null when the client has no email, so there is
	 * nothing to send marketing to and nothing to record consent against.
	 */
	marketing_consent: MarketingConsentState | null;
	/** Whether this member may ask this client for a Google review from the client page. */
	can_request_review?: boolean;
	/** Whether this member may archive or restore this client (customers.archive). */
	can_archive?: boolean;
	/** Whether this member may merge another client into this one (customers.merge). */
	can_merge?: boolean;
	/** The header's three stat tiles. Any figure is null when this member lacks the permission that gates
	 *  it -- the tile then says so instead of showing a wrong or missing number. */
	work_summary: ClientWorkSummary;
};

export type ClientWorkSummary = {
	currency_code: string;
	/** Null without customers.view_financials. */
	lifetime_billed_minor: number | null;
	/** Null without quotes.view. */
	open_quotes_count: number | null;
	/** Null without jobs.view. */
	active_jobs_count: number | null;
};

export type DuplicateCandidates = {
	exact: { id: string; display_name: string; matched_on: 'email' | 'billing_email' | 'phone' }[];
	similar: {
		id: string;
		display_name: string;
		reason: 'name' | 'address';
		detail: string | null;
	}[];
};

// A save that fails for a reason the form can show: bad fields, or a client already using that email
// or phone. Anything else throws a plain Error with a message worth showing.
export class ClientWriteError extends Error {
	fieldErrors: Record<string, string>;
	duplicates: DuplicateCandidates['exact'];

	constructor(
		message: string,
		fieldErrors: Record<string, string>,
		duplicates: DuplicateCandidates['exact']
	) {
		super(message);
		this.name = 'ClientWriteError';
		this.fieldErrors = fieldErrors;
		this.duplicates = duplicates;
	}
}

export const clientsListKey = (filters: ClientListFilters) => ['clients', 'list', filters] as const;

export const clientDetailKey = (clientId: string) => ['clients', 'detail', clientId] as const;

// Carries the HTTP status the server refused with, so the query client stops retrying a 403/404 (the
// answer never changes) and the page can say "no access" or "not found" instead of spinning or blaming
// the connection.
/** `mergedInto` is set on a 404 for a client that was merged into another: the id of the client it became. */
export type ClientReadError = Error & { status: number; mergedInto?: string };

async function readError(response: Response, fallback: string): Promise<ClientReadError> {
	const result = await response
		.json()
		.catch(() => ({}) as { error?: string; merged_into?: string });
	const error = new Error(result.error ?? fallback) as ClientReadError;
	error.status = response.status;
	if (typeof result.merged_into === 'string') error.mergedInto = result.merged_into;
	return error;
}

export async function fetchClient(clientId: string): Promise<ClientDetail> {
	const response = await fetch(`/api/clients/${clientId}`);
	if (!response.ok) throw await readError(response, 'That client could not be loaded.');
	const result = await response.json();
	return result.client;
}

export async function fetchDuplicateCandidates(input: {
	email?: string;
	billingEmail?: string;
	phone?: string;
	name?: string;
	address?: string;
	excludeClientId?: string;
}): Promise<DuplicateCandidates> {
	const params = new URLSearchParams();
	if (input.email) params.set('email', input.email);
	if (input.billingEmail) params.set('billing_email', input.billingEmail);
	if (input.phone) params.set('phone', input.phone);
	if (input.name) params.set('name', input.name);
	if (input.address) params.set('address', input.address);
	if (input.excludeClientId) params.set('exclude_id', input.excludeClientId);

	const response = await fetch(`/api/clients/duplicates?${params.toString()}`);
	if (!response.ok) return { exact: [], similar: [] };
	return response.json();
}

export async function saveClient(values: ClientWriteValues, clientId?: string) {
	const response = await fetch(clientId ? `/api/clients/${clientId}` : '/api/clients', {
		method: clientId ? 'PATCH' : 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(values)
	});

	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new ClientWriteError(
			result.error ?? 'That client could not be saved.',
			result.field_errors ?? {},
			result.duplicates ?? []
		);
	}
	return result.client as { id: string; display_name: string };
}

// Records one owner/admin-recorded marketing-consent change (a real verbal or written preference) into the
// evidence ledger and returns the client's new consent state. Writes on its own the moment it is pressed —
// it is evidence captured at that instant, not something staged with the rest of a client edit.
export async function recordMarketingConsent(
	clientId: string,
	input: { contact_method_id: string; decision: 'opt_in' | 'opt_out'; note?: string }
): Promise<MarketingConsentState> {
	const response = await fetch(`/api/clients/${clientId}/marketing-consent`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});

	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new ClientWriteError(
			result.error ?? 'That consent change could not be recorded.',
			result.field_errors ?? {},
			[]
		);
	}
	return result.marketing_consent as MarketingConsentState;
}

export async function updateProperty(propertyId: string, values: ClientPropertyInput) {
	const response = await fetch(`/api/properties/${propertyId}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(values)
	});

	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new ClientWriteError(
			result.error ?? 'That address could not be saved.',
			result.field_errors ?? {},
			[]
		);
	}
	return result.property as ClientProperty;
}

export async function createProperty(clientId: string, values: ClientPropertyInput) {
	const response = await fetch('/api/properties', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ ...values, client_id: clientId })
	});

	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new ClientWriteError(
			result.error ?? 'That property could not be added.',
			result.field_errors ?? {},
			[]
		);
	}
	return result.property as ClientProperty;
}

/** What deleting a property would take with it, and the records that stop it (empty when nothing does). */
export type PropertyDeleteImpact = {
	requests: number;
	quotes: number;
	jobs: number;
	visits: number;
	blockers: string[];
};

export const propertyDeleteImpactKey = (propertyId: string) =>
	['properties', 'delete-impact', propertyId] as const;

export async function fetchPropertyDeleteImpact(propertyId: string) {
	const response = await fetch(`/api/properties/${propertyId}/delete-impact`);
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw new Error(result.error ?? 'We could not check what this property holds.');
	return result.impact as PropertyDeleteImpact;
}

export async function deleteProperty(propertyId: string) {
	const response = await fetch(`/api/properties/${propertyId}`, { method: 'DELETE' });
	if (response.ok) return;

	const result = await response.json().catch(() => ({}));
	throw new ClientWriteError(
		result.error ?? 'That property could not be removed.',
		result.field_errors ?? {},
		[]
	);
}

/** What merging the secondary client into the primary would move, change, and what stops it. */
export type ClientMergePreview = {
	moves: {
		properties: number;
		contacts: number;
		phones: number;
		emails: number;
		requests: number;
		quotes: number;
		jobs: number;
		invoices: number;
		payments: number;
		messages: number;
		notes: number;
		files: number;
		tags: number;
	};
	/** Plain sentences about what changes on the kept client, such as an opt-out carrying over. */
	warnings: string[];
	/** Plain sentences about what stops the merge right now. Empty when nothing does. */
	blockers: string[];
};

export const clientMergePreviewKey = (primaryId: string, secondaryId: string) =>
	['clients', 'merge-preview', primaryId, secondaryId] as const;

export async function fetchClientMergePreview(primaryId: string, secondaryId: string) {
	const params = new URLSearchParams({ primary: primaryId, secondary: secondaryId });
	const response = await fetch(`/api/clients/merge?${params}`);
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw new Error(result.error ?? 'We could not check these two clients.');
	return result.preview as ClientMergePreview;
}

export async function mergeClients(primaryId: string, secondaryId: string) {
	const response = await fetch('/api/clients/merge', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ primary_client_id: primaryId, secondary_client_id: secondaryId })
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new ClientWriteError(
			result.error ?? 'These clients could not be merged.',
			result.field_errors ?? {},
			[]
		);
	}
	return result as { merge_id: string; surviving_client_id: string };
}

/** What a client still has open, and therefore why archiving them was refused. */
export type ClientOpenWork = {
	requests: number;
	quotes: number;
	jobs: number;
	invoices: number;
};

export type ClientArchiveOutcome = {
	client_id: string;
	applied: boolean;
	archived: boolean;
	open_work: ClientOpenWork | null;
};

/**
 * Archive or restore one client or a selection. Following Jobber, a client is never deleted here — they
 * leave the working list and keep their whole history — and archiving is refused while they still have a
 * live request, quote, job, or unsettled invoice, which comes back as that client's `open_work` counts.
 */
export async function setClientsArchived(clientIds: string[], archived: boolean) {
	const response = await fetch('/api/clients/archive', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ client_ids: clientIds, archived })
	});

	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new ClientWriteError(
			result.error ??
				(archived ? 'That client could not be archived.' : 'That client could not be restored.'),
			result.field_errors ?? {},
			[]
		);
	}
	return result as { changed: number; skipped: number; results: ClientArchiveOutcome[] };
}

export async function fetchClients(
	filters: ClientListFilters,
	cursor?: string
): Promise<ClientListPage> {
	const params = new URLSearchParams();
	if (filters.search) params.set('search', filters.search);
	if (filters.status) params.set('status', filters.status);
	if (filters.tagId) params.set('tag_id', filters.tagId);
	if (filters.sort !== 'updated_at') params.set('sort', filters.sort);
	if (filters.dir !== 'desc') params.set('dir', filters.dir);
	if (cursor) params.set('cursor', cursor);

	const response = await fetch(`/api/clients?${params.toString()}`);
	if (!response.ok) throw await readError(response, 'Clients could not be loaded.');
	return response.json();
}

// --- Client schedule --------------------------------------------------------------------------------------

/** One visit or on-site assessment on the client page's Client schedule. */
export type ClientScheduleEntry = {
	kind: 'visit' | 'assessment';
	id: string;
	/** The job a visit belongs to, or the request an assessment belongs to — what the row opens. */
	record_id: string;
	/** The contractor's own calendar day, YYYY-MM-DD. */
	date: string | null;
	/** A visit's plain wall-clock times; null for an anytime visit and for every assessment. */
	start_time: string | null;
	end_time: string | null;
	/** An assessment's booked instants; null for an all-day one and for every visit. */
	starts_at: string | null;
	ends_at: string | null;
	title: string;
	/** "Job #12" or "Assessment". */
	record_label: string;
	completed: boolean;
	/** Dated before today and never marked done. */
	overdue: boolean;
	assignee_ids: string[];
};

export type ClientSchedule = {
	today: string;
	timezone: string;
	upcoming: ClientScheduleEntry[];
	past: ClientScheduleEntry[];
	has_more_upcoming: boolean;
	has_more_past: boolean;
};

export const clientScheduleKey = (clientId: string) => ['clients', 'schedule', clientId] as const;

export async function fetchClientSchedule(clientId: string): Promise<ClientSchedule> {
	const response = await fetch(`/api/clients/${clientId}/schedule`);
	if (!response.ok) throw await readError(response, "This client's schedule could not be loaded.");
	return response.json();
}
