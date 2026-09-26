import { httpError } from '$lib/http-error';
import type { ReviewChannel, ReviewMessageStyles, ReviewStyle } from './settings';

// Google review campaign Part 3: the manual "Request a review" panel, browser side. The shapes mirror
// public.get_review_request_context and private.review_request_summary.

export type ReviewRequestStatus =
	| 'queued'
	| 'scheduled'
	| 'sent'
	| 'delivered'
	| 'failed'
	| 'cancelled'
	| 'opened'
	| 'continued_to_google'
	| 'feedback_submitted';

export const REVIEW_REQUEST_STATUS_LABELS: Record<ReviewRequestStatus, string> = {
	queued: 'Sending',
	scheduled: 'Scheduled',
	sent: 'Sent',
	delivered: 'Delivered',
	failed: 'Not delivered',
	cancelled: 'Cancelled',
	opened: 'Opened',
	continued_to_google: 'Went to Google',
	feedback_submitted: 'Left private feedback'
};

export const REVIEW_REQUEST_STATUS_TONES: Record<
	ReviewRequestStatus,
	'success' | 'informative' | 'warning' | 'critical' | 'inactive'
> = {
	queued: 'inactive',
	scheduled: 'informative',
	sent: 'informative',
	delivered: 'informative',
	failed: 'critical',
	cancelled: 'inactive',
	opened: 'warning',
	continued_to_google: 'success',
	feedback_submitted: 'success'
};

// Part 4A: why a request's reminders stopped early. A sequence that simply ran out of reminders has none.
export type ReviewRequestStopReason =
	| 'cancelled'
	| 'continued_to_google'
	| 'feedback_submitted'
	| 'not_delivered'
	| 'not_sent'
	| 'client_removed'
	| 'client_opted_out'
	| 'job_not_eligible'
	| 'no_contact'
	| 'plan_changed'
	| 'error';

export const REVIEW_REQUEST_STOP_LABELS: Record<ReviewRequestStopReason, string> = {
	cancelled: 'Cancelled',
	continued_to_google: 'The customer went to Google',
	feedback_submitted: 'The customer left private feedback',
	not_delivered: 'A message could not be delivered',
	not_sent: 'A reminder could not be sent',
	client_removed: 'The client was deleted',
	client_opted_out: 'The client turned off review requests',
	job_not_eligible: 'The job was reopened or is no longer complete',
	no_contact: 'The contact was removed',
	plan_changed: 'Your reminder plan changed',
	error: 'A reminder kept failing to send'
};

export type ReviewRequestMessageState =
	'queued' | 'scheduled' | 'sent' | 'delivered' | 'failed' | 'cancelled';

export type ReviewRequestMessage = {
	// 0 is the first message; 1 and up are reminders.
	slot: number;
	state: ReviewRequestMessageState;
	send_at: string | null;
	sent_at: string | null;
};

export type ReviewRequestSummary = {
	id: string;
	job_id: string | null;
	job_number: number | null;
	channel: ReviewChannel;
	style: ReviewStyle;
	recipient: string | null;
	status: ReviewRequestStatus;
	created_at: string;
	send_at: string | null;
	sent_at: string | null;
	failure_message: string | null;
	messages: ReviewRequestMessage[];
	next_reminder_at: string | null;
	stop_reason: ReviewRequestStopReason | null;
	stop_detail: string | null;
	cancellable: boolean;
};

export type ReviewRequestContact = {
	id: string;
	value: string;
	label: string | null;
	is_primary: boolean;
	contact_name: string | null;
};

export type ReviewRequestContext = {
	business_name: string;
	client: { id: string; name: string; first_name: string | null };
	job: { id: string; job_number: number; title: string | null; eligible: boolean } | null;
	// Only from the client page: the jobs that can be asked about, most recently completed first.
	jobs: { id: string; job_number: number; title: string | null; last_completed_at: string }[];
	phones: (ReviewRequestContact & { sms_consent: 'opted_in' | 'opted_out' | 'unknown' })[];
	emails: (ReviewRequestContact & { suppressed: string | null })[];
	sms_ready: boolean;
	sms_reason: 'no_number' | 'paused' | 'not_ready' | null;
	email_ready: boolean;
	last_asked_at: string | null;
	requests: ReviewRequestSummary[];
	has_google_link: boolean;
	message_styles: ReviewMessageStyles;
	// The current plan's reminder waits, in order: what a request sent now will follow.
	reminder_wait_days: number[];
};

export type ReviewRequestTarget = { jobId: string } | { clientId: string };

export const reviewRequestContextKey = (target: ReviewRequestTarget) =>
	[
		'reviews',
		'request-context',
		'jobId' in target ? `job:${target.jobId}` : `client:${target.clientId}`
	] as const;

async function readError(response: Response, fallback: string) {
	const result = (await response.json().catch(() => ({}))) as {
		error?: string;
		field_errors?: Record<string, string>;
	};
	// The panel has no per-field layout to point at, so the first field's own words beat the generic line.
	return Object.values(result.field_errors ?? {})[0] ?? result.error ?? fallback;
}

export async function fetchReviewRequestContext(
	target: ReviewRequestTarget
): Promise<ReviewRequestContext> {
	const query =
		'jobId' in target
			? `job_id=${encodeURIComponent(target.jobId)}`
			: `client_id=${encodeURIComponent(target.clientId)}`;
	const response = await fetch(`/api/reviews/requests?${query}`);
	if (!response.ok) {
		throw httpError(
			response,
			await readError(response, 'The review request details could not be loaded.')
		);
	}
	return response.json();
}

export type CreateReviewRequestInput = {
	client_id: string;
	job_id: string | null;
	channel: ReviewChannel;
	style: ReviewStyle;
	contact_method_id: string;
	subject: string;
	body: string;
	send_at: string | null;
	idempotency_key: string;
};

export async function createReviewRequest(
	input: CreateReviewRequestInput
): Promise<ReviewRequestSummary> {
	const response = await fetch('/api/reviews/requests', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	if (!response.ok) {
		throw httpError(response, await readError(response, 'The review request could not be sent.'));
	}
	return response.json();
}

export async function cancelReviewRequest(id: string): Promise<ReviewRequestSummary> {
	const response = await fetch(`/api/reviews/requests/${encodeURIComponent(id)}/cancel`, {
		method: 'POST'
	});
	if (!response.ok) {
		throw httpError(
			response,
			await readError(response, 'The review request could not be cancelled.')
		);
	}
	return response.json();
}
