import { json } from '@sveltejs/kit';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { databaseError } from '$lib/server/api/errors';

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
