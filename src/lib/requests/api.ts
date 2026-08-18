import type { DisplayRequestStatus, StoredRequestStatus } from './statuses';

export type RequestListFilters = {
	search: string;
	statuses: StoredRequestStatus[];
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
};

export type RequestStatusCounts = Record<DisplayRequestStatus, number>;

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
	if (cursor) params.set('cursor', cursor);

	const response = await fetch(`/api/requests?${params.toString()}`);
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw new Error(result.error ?? 'Requests could not be loaded.');
	}
	return response.json();
}

export async function fetchRequestCounts(): Promise<RequestStatusCounts> {
	const response = await fetch('/api/requests/counts');
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw new Error(result.error ?? 'The overview could not be loaded.');
	}
	const result = (await response.json()) as { counts: RequestStatusCounts };
	return result.counts;
}
