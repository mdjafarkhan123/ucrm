import { httpError } from '$lib/http-error';
import type { FormQuestion } from '$lib/forms/types';
import type { ReviewChannel } from './settings';

// Google review campaign Part 5B: private-feedback recovery, browser side. Shapes mirror
// public.list_review_feedback.

export const REVIEW_FEEDBACK_STATUSES = ['new', 'contacting', 'resolved', 'closed'] as const;
export type ReviewFeedbackStatus = (typeof REVIEW_FEEDBACK_STATUSES)[number];

export const REVIEW_FEEDBACK_STATUS_LABELS: Record<ReviewFeedbackStatus, string> = {
	new: 'New',
	contacting: 'Contacting customer',
	resolved: 'Resolved',
	closed: 'Closed'
};

export const REVIEW_FEEDBACK_STATUS_TONES: Record<
	ReviewFeedbackStatus,
	'success' | 'informative' | 'warning' | 'critical' | 'inactive'
> = {
	new: 'warning',
	contacting: 'informative',
	resolved: 'success',
	closed: 'inactive'
};

// 'open' is what still needs a person: New and Contacting customer.
export type ReviewFeedbackFilter = ReviewFeedbackStatus | 'open' | 'all';

export type ReviewFeedbackAnswer = string | number | boolean | string[] | null;

export type ReviewFeedbackItem = {
	id: string;
	request_id: string;
	status: ReviewFeedbackStatus;
	rating: number | null;
	submitted_at: string;
	// The questions exactly as the customer saw them.
	questions: FormQuestion[];
	answers: Record<string, ReviewFeedbackAnswer | undefined>;
	channel: ReviewChannel;
	client: { id: string; name: string; email: string | null; phone: string | null } | null;
	job_id: string | null;
	job_number: number | null;
	job_title: string | null;
};

export type ReviewFeedbackPage = {
	feedback: ReviewFeedbackItem[];
	// Null means this was the last page.
	next_cursor: string | null;
};

export type ReviewFeedbackFilters = { search: string; status: ReviewFeedbackFilter };

export const DEFAULT_REVIEW_FEEDBACK_FILTERS: ReviewFeedbackFilters = {
	search: '',
	status: 'open'
};

export const reviewFeedbackKey = (filters: ReviewFeedbackFilters) =>
	['reviews', 'workspace', 'feedback', filters] as const;

async function readError(response: Response, fallback: string) {
	const result = await response.json().catch(() => ({}) as { error?: string });
	return httpError(response, result.error ?? fallback);
}

export async function fetchReviewFeedback(
	filters: ReviewFeedbackFilters,
	cursor?: string
): Promise<ReviewFeedbackPage> {
	const params = new URLSearchParams();
	if (filters.search) params.set('search', filters.search);
	if (filters.status !== 'all') params.set('status', filters.status);
	if (cursor) params.set('cursor', cursor);
	const response = await fetch(`/api/reviews/workspace/feedback?${params}`);
	if (!response.ok) throw await readError(response, 'Private feedback could not be loaded.');
	return response.json();
}

export async function setReviewFeedbackStatus(
	id: string,
	status: ReviewFeedbackStatus
): Promise<void> {
	const response = await fetch(`/api/reviews/feedback/${id}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ status })
	});
	if (!response.ok) throw await readError(response, 'The status could not be changed.');
}

// One customer answer as plain words. A question the customer skipped shows nothing.
export function formatFeedbackAnswer(value: ReviewFeedbackAnswer | undefined): string | null {
	if (value === undefined || value === null || value === '') return null;
	if (typeof value === 'boolean') return value ? 'Yes' : 'No';
	if (Array.isArray(value)) return value.length > 0 ? value.join(', ') : null;
	return String(value);
}
