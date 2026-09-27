import { createHash } from 'node:crypto';
import { json, type RequestEvent } from '@sveltejs/kit';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { databaseError } from '$lib/server/api/errors';
import { ownerSessionIdFromCookie } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

type RateLimitResult = { allowed: boolean; retryAfterSeconds: number };

/**
 * Fixed-window rate limit backed by `public.check_rate_limit` -- one atomic upsert per call, so
 * concurrent requests sharing a bucket key cannot race past the configured limit.
 */
export async function checkRateLimit(
	client: SupabaseClient<Database>,
	options: { bucketKey: string; windowSeconds: number; maxAttempts: number }
): Promise<RateLimitResult> {
	const { data, error } = await client.rpc('check_rate_limit', {
		target_bucket_key: options.bucketKey,
		target_window_seconds: options.windowSeconds,
		target_max_attempts: options.maxAttempts
	});
	if (error) throw error;

	const result = data?.[0];
	if (!result) throw new Error('The rate limit check did not return a result.');

	return { allowed: result.allowed, retryAfterSeconds: result.retry_after_seconds };
}

export function rateLimitedResponse(retryAfterSeconds: number) {
	return json(
		{ error: 'Too many attempts. Please try again shortly.' },
		{ status: 429, headers: { 'Retry-After': String(Math.max(retryAfterSeconds, 1)) } }
	);
}

const ORGANIZATION_WRITE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

/**
 * One shared counter per organization per domain, not one per route -- a caller bouncing between a
 * dozen quote (or invoice, or payment) write routes to dodge a single route's limit still shares this
 * one. Same window/attempts as every other authenticated-write bucket in the app (see the settings
 * routes), so ordinary use never notices it.
 */
export async function enforceOrganizationWriteRateLimit(
	client: SupabaseClient<Database>,
	organizationId: string,
	domain: 'quotes' | 'invoices' | 'payments'
) {
	let limit: RateLimitResult;
	try {
		limit = await checkRateLimit(client, {
			bucketKey: `${domain}-write:${organizationId}`,
			...ORGANIZATION_WRITE_LIMIT
		});
	} catch {
		return databaseError();
	}
	return limit.allowed ? null : rateLimitedResponse(limit.retryAfterSeconds);
}

type RateLimitBucket = { bucketKey: string; windowSeconds: number; maxAttempts: number };

/**
 * An email address as a bucket-key part: hashed, so the counter table never holds anyone's address, and
 * lower-cased first, so `Info@x.com` and `info@x.com` share one budget.
 */
export function emailBucketPart(email: string) {
	return createHash('sha256').update(email.trim().toLowerCase()).digest('hex');
}

/**
 * Limits for login and password calls. Supabase Auth's own per-address limits cannot tell visitors apart
 * here, because it sees only this server's address, so the app keeps its own. The counter runs on the
 * service client, since a signed-out visitor may not call it. It fails open, like the
 * front-door limit: a counting problem must never stop every contractor from signing in.
 */
export async function enforceAuthRateLimits(buckets: RateLimitBucket[]) {
	let results: RateLimitResult[];
	try {
		const client = getOwnerSupabaseClient();
		results = await Promise.all(buckets.map((bucket) => checkRateLimit(client, bucket)));
	} catch (error) {
		console.error('A sign-in rate limit could not be checked; letting the request through.', error);
		return null;
	}
	const refused = results.filter((result) => !result.allowed);
	if (refused.length === 0) return null;
	return rateLimitedResponse(Math.max(...refused.map((result) => result.retryAfterSeconds)));
}

// Per person, per minute. Loose enough that opening pages, hovering links (each hover prefetches) and
// editing never meet it; tight enough that a stuck loop or a stolen session scraping the CRM is stopped
// within seconds. Reads and writes have separate budgets, the way GitHub and Stripe count them.
const API_READ_LIMIT = { windowSeconds: 60, maxAttempts: 600 };
const API_WRITE_LIMIT = { windowSeconds: 60, maxAttempts: 120 };

/**
 * The front-door limit every signed-in `/api/*` request passes, whatever gate the route itself uses. It
 * keys on who is asking -- a contractor's user id, or the Jafar Panel session -- so one busy teammate
 * never spends the rest of the team's budget. A request with no identity (webhooks, workers, public
 * links) is left to that route's own protection. The per-route and per-organization limits still apply
 * inside this one.
 *
 * It fails open: if the counter itself cannot be reached, the request goes through rather than locking
 * every contractor out of their CRM over a counting problem.
 */
export async function enforceApiRateLimit(event: RequestEvent, userId: string | null) {
	const { pathname } = event.url;
	const method = event.request.method;
	if (!pathname.startsWith('/api/') || method === 'OPTIONS') return null;

	let caller: { key: string; client: SupabaseClient<Database> } | null = null;
	if (pathname.startsWith('/api/jafar/')) {
		const sessionId = ownerSessionIdFromCookie(event);
		if (sessionId) caller = { key: `owner:${sessionId}`, client: getOwnerSupabaseClient() };
	} else if (userId) {
		caller = { key: `user:${userId}`, client: event.locals.supabase };
	}
	if (!caller) return null;

	const isRead = method === 'GET' || method === 'HEAD';
	try {
		const limit = await checkRateLimit(caller.client, {
			bucketKey: `api-${isRead ? 'read' : 'write'}:${caller.key}`,
			...(isRead ? API_READ_LIMIT : API_WRITE_LIMIT)
		});
		return limit.allowed ? null : rateLimitedResponse(limit.retryAfterSeconds);
	} catch (error) {
		console.error('The API rate limit could not be checked; letting the request through.', error);
		return null;
	}
}
