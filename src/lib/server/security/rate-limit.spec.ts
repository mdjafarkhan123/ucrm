import { beforeEach, describe, expect, it, vi } from 'vitest';
import { emailBucketPart, enforceApiRateLimit, enforceAuthRateLimits } from './rate-limit';
import { ownerSessionIdFromCookie } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ ownerSessionIdFromCookie: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const USER_ID = '22222222-2222-2222-2222-222222222222';

function counter(result: { allowed: boolean; retry_after_seconds: number } | Error) {
	return {
		rpc: vi.fn(async () =>
			result instanceof Error ? { data: null, error: result } : { data: [result], error: null }
		)
	};
}

function fakeEvent(path: string, method: string, client: ReturnType<typeof counter>) {
	return {
		url: new URL(`https://app.example.com${path}`),
		request: new Request(`https://app.example.com${path}`, { method }),
		locals: { supabase: client }
	} as never;
}

describe('enforceApiRateLimit', () => {
	beforeEach(() => vi.clearAllMocks());

	it('counts a signed-in read against that person’s read budget', async () => {
		const client = counter({ allowed: true, retry_after_seconds: 0 });
		const result = await enforceApiRateLimit(fakeEvent('/api/jobs', 'GET', client), USER_ID);

		expect(result).toBeNull();
		expect(client.rpc).toHaveBeenCalledWith('check_rate_limit', {
			target_bucket_key: `api-read:user:${USER_ID}`,
			target_window_seconds: 60,
			target_max_attempts: 600
		});
	});

	it('counts a save against a separate, smaller write budget', async () => {
		const client = counter({ allowed: true, retry_after_seconds: 0 });
		await enforceApiRateLimit(fakeEvent('/api/clients', 'PATCH', client), USER_ID);

		expect(client.rpc).toHaveBeenCalledWith('check_rate_limit', {
			target_bucket_key: `api-write:user:${USER_ID}`,
			target_window_seconds: 60,
			target_max_attempts: 120
		});
	});

	it('answers 429 with Retry-After once the budget is spent', async () => {
		const client = counter({ allowed: false, retry_after_seconds: 17 });
		const result = await enforceApiRateLimit(fakeEvent('/api/jobs', 'GET', client), USER_ID);

		expect(result?.status).toBe(429);
		expect(result?.headers.get('Retry-After')).toBe('17');
	});

	it('lets the request through when the counter cannot be reached', async () => {
		vi.spyOn(console, 'error').mockImplementation(() => {});
		const client = counter(new Error('connection refused'));
		const result = await enforceApiRateLimit(fakeEvent('/api/jobs', 'POST', client), USER_ID);

		expect(result).toBeNull();
	});

	it('leaves requests with no identity, pages, and preflights alone', async () => {
		const client = counter({ allowed: false, retry_after_seconds: 5 });

		expect(
			await enforceApiRateLimit(fakeEvent('/api/webhooks/stripe/x', 'POST', client), null)
		).toBeNull();
		expect(await enforceApiRateLimit(fakeEvent('/jobs', 'GET', client), USER_ID)).toBeNull();
		expect(
			await enforceApiRateLimit(fakeEvent('/api/jobs', 'OPTIONS', client), USER_ID)
		).toBeNull();
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('keys Jafar Panel requests on the owner session, not a contractor login in the same browser', async () => {
		const ownerClient = counter({ allowed: true, retry_after_seconds: 0 });
		vi.mocked(ownerSessionIdFromCookie).mockReturnValue('session-1');
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(ownerClient as never);
		const contractorClient = counter({ allowed: true, retry_after_seconds: 0 });

		await enforceApiRateLimit(
			fakeEvent('/api/jafar/organizations', 'GET', contractorClient),
			USER_ID
		);

		expect(contractorClient.rpc).not.toHaveBeenCalled();
		expect(ownerClient.rpc).toHaveBeenCalledWith(
			'check_rate_limit',
			expect.objectContaining({ target_bucket_key: 'api-read:owner:session-1' })
		);
	});

	it('skips a Jafar Panel request without a valid owner session, such as a scheduled job', async () => {
		vi.mocked(ownerSessionIdFromCookie).mockReturnValue(null);
		const client = counter({ allowed: false, retry_after_seconds: 5 });

		const result = await enforceApiRateLimit(
			fakeEvent('/api/jafar/internal/closure-cron', 'POST', client),
			null
		);

		expect(result).toBeNull();
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});
});

describe('enforceAuthRateLimits', () => {
	beforeEach(() => vi.clearAllMocks());

	const bucket = { bucketKey: 'login:address:1.2.3.4', windowSeconds: 900, maxAttempts: 50 };

	it('passes when every bucket still has room', async () => {
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(
			counter({ allowed: true, retry_after_seconds: 0 }) as never
		);
		expect(await enforceAuthRateLimits([bucket, bucket])).toBeNull();
	});

	it('answers 429 when any bucket is spent', async () => {
		const client = {
			rpc: vi
				.fn()
				.mockResolvedValueOnce({ data: [{ allowed: true, retry_after_seconds: 0 }], error: null })
				.mockResolvedValueOnce({ data: [{ allowed: false, retry_after_seconds: 42 }], error: null })
		};
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const result = await enforceAuthRateLimits([bucket, bucket]);
		expect(result?.status).toBe(429);
		expect(result?.headers.get('Retry-After')).toBe('42');
	});

	it('lets the attempt through when the counter cannot be reached', async () => {
		vi.spyOn(console, 'error').mockImplementation(() => {});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(counter(new Error('down')) as never);
		expect(await enforceAuthRateLimits([bucket])).toBeNull();
	});

	it('never stores the email itself, and ignores letter case', () => {
		expect(emailBucketPart('Info@Example.com')).toBe(emailBucketPart('info@example.com'));
		expect(emailBucketPart('info@example.com')).not.toContain('example');
	});
});
