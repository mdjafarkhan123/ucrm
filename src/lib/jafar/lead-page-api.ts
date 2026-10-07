import type { QueryClient } from '@tanstack/svelte-query';
import type { ApplicationCandidate, HistoryPage, LeadPage } from './lead-history';
import {
	jafarHomeKey,
	jafarLeadApplicationCandidatesKey,
	jafarLeadKey,
	jafarLeadReviewKey,
	jafarLeadsKey
} from './query-keys';

// Jafar business management B2: the browser side of the Lead page's routes. Every write answers the same
// shape, so each form shows the server's own words against the field they belong to.

export type WriteResult =
	| { ok: true; data: Record<string, unknown> }
	| { ok: false; error: string; fieldErrors: Record<string, string> };

export async function fetchLeadPage(leadId: string): Promise<LeadPage> {
	const response = await fetch(`/api/jafar/leads/${encodeURIComponent(leadId)}`);
	const result = await response.json();
	if (!response.ok) {
		const error = new Error(result.error ?? 'This Lead could not be loaded.') as Error & {
			status?: number;
		};
		error.status = response.status;
		throw error;
	}
	return result as LeadPage;
}

export async function fetchOlderHistory(leadId: string, cursor: string): Promise<HistoryPage> {
	const response = await fetch(
		`/api/jafar/leads/${encodeURIComponent(leadId)}/history?cursor=${encodeURIComponent(cursor)}`
	);
	const result = await response.json();
	if (!response.ok) throw new Error(result.error ?? 'Older history could not be loaded.');
	return result as HistoryPage;
}

export async function sendLeadWrite(
	path: string,
	method: 'POST' | 'PATCH' | 'DELETE',
	body?: unknown
): Promise<WriteResult> {
	try {
		const response = await fetch(path, {
			method,
			headers: body === undefined ? undefined : { 'content-type': 'application/json' },
			body: body === undefined ? undefined : JSON.stringify(body)
		});
		const result = await response.json().catch(() => ({}));
		if (response.ok) return { ok: true, data: result };
		const fieldErrors: Record<string, string> = result.field_errors ?? {};
		// A refusal about the whole form reads better than the generic "review the highlighted fields".
		const error = fieldErrors.form ?? result.error ?? 'That could not be saved. Please try again.';
		return { ok: false, error, fieldErrors };
	} catch {
		return { ok: false, error: 'You seem to be offline. Please try again.', fieldErrors: {} };
	}
}

/** After any change on a Lead: its page (and older history under it), the Leads list, the review queue, and the
 * home's counts and to-do list. */
export function refreshLead(queryClient: QueryClient, leadId: string) {
	return Promise.all([
		queryClient.invalidateQueries({ queryKey: jafarHomeKey }),
		queryClient.invalidateQueries({ queryKey: jafarLeadKey(leadId) }),
		queryClient.invalidateQueries({ queryKey: [...jafarLeadsKey, 'list'] }),
		queryClient.invalidateQueries({ queryKey: jafarLeadReviewKey })
	]);
}

export async function fetchApplicationCandidates(
	leadId: string,
	search: string
): Promise<ApplicationCandidate[]> {
	const query = search ? `?search=${encodeURIComponent(search)}` : '';
	const response = await fetch(
		`/api/jafar/leads/${encodeURIComponent(leadId)}/applications${query}`
	);
	const result = await response.json();
	if (!response.ok) throw new Error(result.error ?? 'Applications could not be loaded.');
	return result.applications as ApplicationCandidate[];
}

export const APPLICATION_CANDIDATES_STALE_MS = 30_000;

/** Warms the "Link an Application" picker while the pointer is on its button. */
export function prefetchApplicationCandidates(queryClient: QueryClient, leadId: string) {
	return queryClient.prefetchQuery({
		queryKey: jafarLeadApplicationCandidatesKey(leadId, ''),
		queryFn: () => fetchApplicationCandidates(leadId, ''),
		staleTime: APPLICATION_CANDIDATES_STALE_MS
	});
}
