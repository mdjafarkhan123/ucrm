// Google review campaign Part 2: a review request's customer link, from both ends -- the same shape the file
// share link proved out. A token is made here, hashed here, and the hash is the only form that ever leaves
// this file towards the database. The link never expires; it works until the request is cancelled.

import { createHash, randomBytes } from 'node:crypto';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	DEFAULT_REVIEW_FEEDBACK_FORM,
	DEFAULT_ROUTING_GOOGLE_MIN_RATING,
	type ReviewFeedbackForm
} from '$lib/reviews/settings';

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
