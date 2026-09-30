import { httpError, type HttpError } from '$lib/http-error';
import type { ReviewRequestStatus, ReviewRequestSummary } from './requests';
import type { ReviewChannel } from './settings';

// Google review campaign Part 5A: the Reviews workspace, browser side. Shapes mirror
// public.list_review_requests and public.review_request_counts.

export type ReviewWorkspaceRequest = ReviewRequestSummary & {
	client: { id: string; name: string } | null;
	job_title: string | null;
	rating: number | null;
	opened_at: string | null;
	continued_to_google_at: string | null;
	feedback_submitted_at: string | null;
	cancelled_at: string | null;
};

export type ReviewWorkspaceFilters = {
	search: string;
	status: ReviewRequestStatus | '';
	channel: ReviewChannel | '';
};

export type ReviewWorkspacePage = {
	requests: ReviewWorkspaceRequest[];
	// Null means this was the last page.
	next_cursor: string | null;
};

export type ReviewWorkspaceCounts = {
	asked: number;
	opened: number;
	went_to_google: number;
	private_feedback: number;
	// Null when the member may not see private feedback.
	new_feedback: number | null;
};

export const reviewWorkspaceRequestsKey = (filters: ReviewWorkspaceFilters) =>
	['reviews', 'workspace', 'requests', filters] as const;
export const reviewWorkspaceCountsKey = ['reviews', 'workspace', 'counts'] as const;
// Everything the workspace caches, for invalidating after a request is cancelled.
export const reviewWorkspaceKey = ['reviews', 'workspace'] as const;

// The reason tells "not in your plan" apart from "not allowed", so the page can say which.
async function readError(response: Response, fallback: string) {
	const result = await response.json().catch(() => ({}) as { error?: string; reason?: string });
	const error = httpError(response, result.error ?? fallback) as HttpError & { reason?: string };
	error.reason = result.reason;
	return error;
}

export async function fetchReviewWorkspaceRequests(
	filters: ReviewWorkspaceFilters,
	cursor?: string
): Promise<ReviewWorkspacePage> {
	const params = new URLSearchParams();
	if (filters.search) params.set('search', filters.search);
	if (filters.status) params.set('status', filters.status);
	if (filters.channel) params.set('channel', filters.channel);
	if (cursor) params.set('cursor', cursor);
	const response = await fetch(`/api/reviews/workspace/requests?${params}`);
	if (!response.ok) throw await readError(response, 'Review requests could not be loaded.');
	return response.json();
}

export async function fetchReviewWorkspaceCounts(): Promise<ReviewWorkspaceCounts> {
	const response = await fetch('/api/reviews/workspace/counts');
	if (!response.ok) throw await readError(response, 'Review numbers could not be loaded.');
	return response.json();
}
