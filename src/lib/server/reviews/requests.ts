// Google review campaign Part 2: a review request's customer link, from both ends -- the same shape the file
// share link proved out. A token is made here, hashed here, and the hash is the only form that ever leaves
// this file towards the database. The link never expires; it works until the request is cancelled.

import { createHash, randomBytes } from 'node:crypto';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	DEFAULT_REVIEW_FEEDBACK_FORM,
	DEFAULT_REVIEW_MESSAGE_STYLES,
	DEFAULT_REVIEW_REQUEST_PLAN,
	DEFAULT_ROUTING_GOOGLE_MIN_RATING,
	type ReviewChannel,
	type ReviewFeedbackForm,
	type ReviewMessageStyles,
	type ReviewRequestPlan,
	type ReviewStyle
} from '$lib/reviews/settings';
import type { ReviewRequestContext, ReviewRequestSummary } from '$lib/reviews/requests';

const TOKEN_BYTES = 32;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

function hashLiteral(token: string) {
	return `\\x${createHash('sha256').update(token, 'utf8').digest('hex')}`;
}

export function createReviewRequestToken() {
	const token = randomBytes(TOKEN_BYTES).toString('base64url');
	return { token, tokenHash: hashLiteral(token) };
}

// A token that is not the right shape is answered without touching the database at all.
export function reviewRequestTokenHash(token: string | undefined) {
	if (!token || !TOKEN_PATTERN.test(token)) return null;
	return hashLiteral(token);
}

export function reviewRequestUrl(origin: string, token: string) {
	return `${origin}/v/${token}`;
}

export type ResolvedReviewRequest = {
	business: { name: string; logo_object_key: string | null };
	customer_first_name: string | null;
	google_review_url: string | null;
	routing_enabled: boolean;
	routing_google_min_rating: number;
	feedback_form: ReviewFeedbackForm;
	rating: number | null;
	feedback_submitted: boolean;
};

type ResolverRow = {
	business: { name: string; logo_object_key: string | null };
	customer_first_name: string | null;
	settings: {
		google_review_url: string | null;
		routing_enabled: boolean;
		routing_google_min_rating: number;
		feedback_form: ReviewFeedbackForm;
	} | null;
	rating: number | null;
	feedback_submitted: boolean;
};

// The public page has no signed-in user. It runs as the service role, whose only review-request privilege
// is the reader and recorder functions. Made once per process.
let serviceClient: ReturnType<typeof getOwnerSupabaseClient> | null = null;

export function getReviewRequestClient() {
	serviceClient ??= getOwnerSupabaseClient();
	return serviceClient;
}

/** Null for a link that never existed, was cancelled, or whose client was deleted -- all alike. */
export async function resolveReviewRequest(
	tokenHash: string
): Promise<ResolvedReviewRequest | null> {
	const { data, error } = await getReviewRequestClient().rpc('resolve_review_request', {
		supplied_token_hash: tokenHash
	});
	// Deliberately not logged with the token: a failure is a broken link or somebody guessing.
	if (error || !data) return null;

	const row = data as unknown as ResolverRow;
	const settings = row.settings;
	return {
		business: row.business,
		customer_first_name: row.customer_first_name,
		google_review_url: settings?.google_review_url ?? null,
		routing_enabled: settings?.routing_enabled ?? false,
		routing_google_min_rating:
			settings?.routing_google_min_rating ?? DEFAULT_ROUTING_GOOGLE_MIN_RATING,
		feedback_form: settings?.feedback_form ?? DEFAULT_REVIEW_FEEDBACK_FORM,
		rating: row.rating,
		feedback_submitted: row.feedback_submitted
	};
}

// Rate-limit buckets for the public page's calls: one per address, one per link.
export function reviewRequestIpBucketKey(action: string, ipAddress: string) {
	return `review_request_public_${action}_ip:${createHash('sha256').update(ipAddress, 'utf8').digest('hex')}`;
}

export function reviewRequestTokenBucketKey(action: string, tokenHashLiteral: string) {
	return `review_request_public_${action}_token:${tokenHashLiteral.slice(2)}`;
}

// Both locks at once: a person tapping around, and one link being hammered from many addresses.
export async function checkReviewRequestLimits(
	action: string,
	ipAddress: string,
	tokenHash: string,
	limits: { windowSeconds: number; perAddress: number; perLink: number }
) {
	const client = getReviewRequestClient();
	const [byAddress, byLink] = await Promise.all([
		checkRateLimit(client, {
			bucketKey: reviewRequestIpBucketKey(action, ipAddress),
			windowSeconds: limits.windowSeconds,
			maxAttempts: limits.perAddress
		}),
		checkRateLimit(client, {
			bucketKey: reviewRequestTokenBucketKey(action, tokenHash),
			windowSeconds: limits.windowSeconds,
			maxAttempts: limits.perLink
		})
	]);
	if (!byAddress.allowed) return rateLimitedResponse(byAddress.retryAfterSeconds);
	if (!byLink.allowed) return rateLimitedResponse(byLink.retryAfterSeconds);
	return null;
}

// ---------------------------------------------------------------------------------------------------------
// Google review campaign Part 3: the manual "Request a review" panel. The member's reviews.request permission
// is checked by the route; each database function checks it again, with its scope, for the exact job.

export class ReviewRequestRefusedError extends Error {
	constructor(
		message: string,
		readonly status: number
	) {
		super(message);
	}
}

// Refusals the database words for the contractor already: permission and scope, a missing client, job or
// contact, a job with no completed work, texting consent, length, SMS balance and a sender not set up.
const REFUSAL_STATUS: Record<string, number> = {
	'42501': 403,
	P0002: 404,
	'23503': 422,
	'23514': 422,
	'55000': 422,
	P0001: 422,
	P0402: 422,
	'23505': 409
};

function refusalFrom(error: { code?: string; message: string }) {
	const status = REFUSAL_STATUS[error.code ?? ''];
	return status ? new ReviewRequestRefusedError(error.message, status) : null;
}

async function loadReviewMessageSetup(organizationId: string) {
	const { data, error } = await getReviewRequestClient()
		.from('review_settings')
		.select('google_review_url, message_styles, request_plan')
		.eq('organization_id', organizationId)
		.maybeSingle();
	if (error) throw error;
	return {
		google_review_url: data?.google_review_url ?? null,
		message_styles:
			(data?.message_styles as ReviewMessageStyles | undefined) ?? DEFAULT_REVIEW_MESSAGE_STYLES,
		request_plan:
			(data?.request_plan as ReviewRequestPlan | null | undefined) ?? DEFAULT_REVIEW_REQUEST_PLAN
	};
}

/** Null when the job or client is not found, or this member may not ask about it. */
export async function loadReviewRequestContext(
	organizationId: string,
	actorId: string,
	target: { jobId: string | null; clientId: string | null }
): Promise<ReviewRequestContext | null> {
	const [context, setup] = await Promise.all([
		getReviewRequestClient().rpc('get_review_request_context', {
			p_organization_id: organizationId,
			p_actor_id: actorId,
			p_client_id: target.clientId as string,
			p_job_id: target.jobId as string
		}),
		loadReviewMessageSetup(organizationId)
	]);
	if (context.error) throw context.error;
	if (!context.data) return null;
	return {
		...(context.data as unknown as Omit<
			ReviewRequestContext,
			'has_google_link' | 'message_styles' | 'reminder_wait_days'
		>),
		has_google_link: Boolean(setup.google_review_url),
		message_styles: setup.message_styles,
		reminder_wait_days: setup.request_plan.reminders.map((reminder) => reminder.wait_days)
	};
}

const MESSAGE_TOKEN = /\{\{([a-z_]+)\}\}/g;

/** Swaps each review variable for its value. The link stays a placeholder until the email is rendered. */
export function fillReviewMessage(template: string, values: Record<string, string>) {
	return template.replace(MESSAGE_TOKEN, (match, token: string) => values[token] ?? match);
}

const HTML_ESCAPE: Record<string, string> = {
	'&': '&amp;',
	'<': '&lt;',
	'>': '&gt;',
	'"': '&quot;',
	"'": '&#39;'
};

function escapeHtml(value: string) {
	return value.replace(/[&<>"']/g, (character) => HTML_ESCAPE[character] ?? character);
}

// Plain text in, as the manual email renderer does it, with the one review link made clickable. The link is
// our own /v/<token> URL, so escaping it changes nothing and the database still finds it in the HTML.
export function renderReviewEmailHtml(text: string, linkUrl: string) {
	const link = escapeHtml(linkUrl);
	const body = text
		.split(linkUrl)
		.map((part) => escapeHtml(part))
		.join(`<a href="${link}">${link}</a>`);
	return `<p>${body.replace(/\r?\n/g, '<br>')}</p>`;
}

export type SendReviewRequestInput = {
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

export async function sendReviewRequest(
	organizationId: string,
	actorId: string,
	origin: string,
	input: SendReviewRequestInput
): Promise<ReviewRequestSummary> {
	const context = await loadReviewRequestContext(organizationId, actorId, {
		jobId: input.job_id,
		clientId: input.client_id
	});
	if (!context || context.client.id !== input.client_id) {
		throw new ReviewRequestRefusedError(
			'You do not have permission to ask this customer for a review.',
			403
		);
	}
	if (!context.has_google_link) {
		throw new ReviewRequestRefusedError(
			'Add your Google review link in Review settings before asking for reviews.',
			422
		);
	}

	const contacts = input.channel === 'sms' ? context.phones : context.emails;
	const contact = contacts.find((method) => method.id === input.contact_method_id);
	// Someone at the contact's own name is greeted by it; the client's own number by the client's.
	const fullName = contact?.contact_name ?? context.client.name;
	const firstName = contact?.contact_name
		? contact.contact_name.split(/\s+/)[0]
		: (context.client.first_name ?? context.client.name.split(/\s+/)[0]);

	const { token, tokenHash } = createReviewRequestToken();
	const linkUrl = reviewRequestUrl(origin, token);
	const values = {
		customer_first_name: firstName,
		customer_name: fullName,
		business_name: context.business_name,
		review_link: linkUrl
	};
	const bodyText = fillReviewMessage(input.body, values);
	const subject = input.channel === 'email' ? fillReviewMessage(input.subject, values) : '';

	const { data, error } = await getReviewRequestClient().rpc('create_review_request', {
		p_organization_id: organizationId,
		p_actor_id: actorId,
		p_client_id: input.client_id,
		p_job_id: input.job_id as string,
		p_channel: input.channel,
		p_style: input.style,
		p_contact_method_id: input.contact_method_id,
		p_subject: subject,
		p_body_text: bodyText,
		p_body_html: input.channel === 'email' ? renderReviewEmailHtml(bodyText, linkUrl) : '',
		p_link_url: linkUrl,
		p_token_hash: tokenHash,
		p_send_at: input.send_at as string,
		// The plan as it stands now; each later reminder re-reads it when it comes due.
		p_first_reminder_days: (context.reminder_wait_days[0] ?? null) as number,
		p_idempotency_key: input.idempotency_key
	});
	if (error) throw refusalFrom(error) ?? error;
	return data as unknown as ReviewRequestSummary;
}

export async function cancelReviewRequest(
	organizationId: string,
	actorId: string,
	requestId: string
): Promise<ReviewRequestSummary> {
	const { data, error } = await getReviewRequestClient().rpc('cancel_review_request', {
		p_organization_id: organizationId,
		p_actor_id: actorId,
		p_request_id: requestId
	});
	if (error) throw refusalFrom(error) ?? error;
	return data as unknown as ReviewRequestSummary;
}
