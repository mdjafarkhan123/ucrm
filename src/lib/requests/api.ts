import type { DisplayRequestStatus, StoredRequestStatus } from './statuses';
import type { CustomerNoticeSent } from '$lib/schedule/customer-notices';

export type RequestSortKey = 'requested' | 'title';

export type RequestListFilters = {
	search: string;
	statuses: DisplayRequestStatus[];
	sort: RequestSortKey;
	dir: 'asc' | 'desc';
	/** One client's records only — the client page's Work overview. Unset on the ordinary list. */
	client_id?: string;
	/** Rows per page when a caller needs fewer than the list's default. */
	limit?: number;
};

export type RequestListItem = {
	id: string;
	title: string;
	service_type: string | null;
	requested_at: string;
	stored_status: StoredRequestStatus;
	status: DisplayRequestStatus;
	client: { id: string; display_name: string; company_name: string | null } | null;
	property: {
		id: string;
		label: string | null;
		address_line1: string;
		city: string;
		state_region: string | null;
		postal_code: string | null;
	} | null;
	assessment: {
		id: string;
		starts_at: string | null;
		ends_at: string | null;
		all_day: boolean;
		completed_at: string | null;
	} | null;
	email: string | null;
	phone: string | null;
};

export type RequestListPage = {
	requests: RequestListItem[];
	// Null means this was the last page. The list is keyset paginated, so there is no page number to
	// jump to — the cursor is the only way to ask for what comes next.
	next_cursor: string | null;
	/** More clients matched the search than the list could include; see clientNameSearchBranch. */
	search_narrowed?: boolean;
};

export type RequestStatusCounts = Record<DisplayRequestStatus, number>;

/** One 30-day window's requests: how many were created, and how many of those became a quote or job. */
export type RequestWindow = { new: number; converted: number };

export type RequestOverview = {
	counts: RequestStatusCounts;
	last_30_days: RequestWindow;
	previous_30_days: RequestWindow;
};

export const requestsListKey = (filters: RequestListFilters) =>
	['requests', 'list', filters] as const;
export const requestCountsKey = ['requests', 'counts'] as const;

export async function fetchRequests(
	filters: RequestListFilters,
	cursor?: string
): Promise<RequestListPage> {
	const params = new URLSearchParams();
	if (filters.search) params.set('search', filters.search);
	for (const status of filters.statuses) params.append('status', status);
	if (filters.sort !== 'requested') params.set('sort', filters.sort);
	if (filters.dir !== 'desc') params.set('dir', filters.dir);
	if (filters.client_id) params.set('client_id', filters.client_id);
	if (filters.limit) params.set('limit', String(filters.limit));
	if (cursor) params.set('cursor', cursor);

	const response = await fetch(`/api/requests?${params.toString()}`);
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw new Error(result.error ?? 'Requests could not be loaded.');
	}
	return response.json();
}

export async function fetchRequestCounts(): Promise<RequestOverview> {
	const response = await fetch('/api/requests/counts');
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw new Error(result.error ?? 'The overview could not be loaded.');
	}
	return response.json();
}

// --- The detail page ------------------------------------------------------------------------------

export type RequestAssessment = {
	id: string;
	starts_at: string | null;
	ends_at: string | null;
	all_day: boolean;
	instructions: string | null;
	completed_at: string | null;
	assignee_ids: string[];
};

export type RequestDetail = {
	id: string;
	client_id: string;
	property_id: string;
	title: string;
	description: string | null;
	service_type: string | null;
	source: string | null;
	preferred_time: string | null;
	created_at: string;
	updated_at: string;
	stored_status: StoredRequestStatus;
	status: DisplayRequestStatus;
	/** The organization's own timezone, so the on-site assessment books in the office's clock, not the browser's. */
	timezone: string;
	client: {
		id: string;
		display_name: string;
		company_name: string | null;
		client_type: string;
	} | null;
	property: {
		id: string;
		label: string | null;
		address_line1: string;
		address_line2: string | null;
		city: string;
		state_region: string | null;
		postal_code: string | null;
		country: string | null;
		access_notes: string | null;
	} | null;
	assessment: RequestAssessment | null;
	/** The job or quote a converted request became. Null while it is live, or when the reader may not see it. */
	converted_to: { kind: 'job' | 'quote'; id: string; number: number } | null;
	email: string | null;
	phone: string | null;
};

export const requestDetailKey = (id: string) => ['requests', 'detail', id] as const;

export type RequestCreateInput = {
	client_id: string;
	property_id: string;
	title: string;
	description?: string;
};

export async function createRequest(input: RequestCreateInput) {
	const response = await fetch('/api/requests', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	const result = await readOrThrow<{ request: { id: string; title: string } }>(
		response,
		'That request could not be saved.'
	);
	return result.request;
}

/** What the on-site assessment panel sends. Both times null is Jobber's "booked but not scheduled yet". */
export type AssessmentDraft = {
	starts_at: string | null;
	ends_at: string | null;
	all_day: boolean;
	instructions: string | null;
	assignee_ids: string[];
};

// The HTTP status the server refused with. A reader who is not allowed to see a request gets the same
// answer however many times they ask, so callers use this to stop retrying and to say what actually
// happened instead of a generic failure.
export type RequestWriteError = Error & { fieldErrors?: Record<string, string>; status?: number };

async function readOrThrow<T>(response: Response, fallback: string): Promise<T> {
	if (!response.ok) {
		const result = await response
			.json()
			.catch(() => ({}) as { error?: string; field_errors?: Record<string, string> });
		const error = new Error(result.error ?? fallback) as RequestWriteError;
		error.fieldErrors = result.field_errors ?? {};
		error.status = response.status;
		throw error;
	}
	return response.json();
}

export async function fetchRequest(id: string): Promise<RequestDetail> {
	const response = await fetch(`/api/requests/${id}`);
	const result = await readOrThrow<{ request: RequestDetail }>(
		response,
		'That request could not be loaded.'
	);
	return result.request;
}

// Every block on the page owns a few fields and saves only those, so this takes whatever it is given.
export async function patchRequest(id: string, patch: Record<string, unknown>) {
	const response = await fetch(`/api/requests/${id}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(patch)
	});
	return readOrThrow<{ request: { id: string } }>(response, 'That change could not be saved.');
}

export async function saveAssessment(id: string, draft: AssessmentDraft, notifyCustomer = false) {
	const response = await fetch(`/api/requests/${id}/assessment`, {
		method: 'PUT',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ ...draft, notify_customer: notifyCustomer })
	});
	return readOrThrow<{ assessment: RequestAssessment; customer_notice?: CustomerNoticeSent }>(
		response,
		'The assessment could not be saved.'
	);
}

export async function removeAssessment(id: string) {
	const response = await fetch(`/api/requests/${id}/assessment`, { method: 'DELETE' });
	return readOrThrow<{ deleted: boolean }>(response, 'The assessment could not be removed.');
}

export async function completeAssessment(id: string, complete: boolean) {
	const response = await fetch(`/api/requests/${id}/assessment/complete`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ complete })
	});
	return readOrThrow<{ assessment: RequestAssessment }>(
		response,
		complete
			? 'The assessment could not be marked complete.'
			: 'The assessment could not be reopened.'
	);
}
