import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DELETE, POST } from './+server';
import {
	clearOwnerSession,
	ownerLoginRateLimitBucketKey,
	recordOwnerLoginAttempt,
	setOwnerSession,
	verifyOwnerCredentials
} from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/auth/owner', () => ({
	clearOwnerSession: vi.fn(),
	ownerLoginRateLimitBucketKey: vi.fn(() => 'owner_login:hashed-ip'),
	recordOwnerLoginAttempt: vi.fn(),
	setOwnerSession: vi.fn(),
	verifyOwnerCredentials: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));

const mockedVerify = vi.mocked(verifyOwnerCredentials);
const mockedSetSession = vi.mocked(setOwnerSession);
const mockedClearSession = vi.mocked(clearOwnerSession);
const mockedRecordAttempt = vi.mocked(recordOwnerLoginAttempt);
const mockedBucketKey = vi.mocked(ownerLoginRateLimitBucketKey);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedCheckRateLimit = vi.mocked(checkRateLimit);

function postEvent(body: unknown) {
	return {
		request: new Request('http://localhost/api/jafar/session', {
			method: 'POST',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		cookies: {},
		getClientAddress: () => '203.0.113.10'
	} as Parameters<typeof POST>[0];
}

describe('platform owner session API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedClient.mockReturnValue({} as never);
		mockedCheckRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
	});

	it('rejects a request body that is not valid JSON', async () => {
		const response = await POST({
			request: new Request('http://localhost/api/jafar/session', {
				method: 'POST',
				body: 'not json',
				headers: { 'content-type': 'application/json' }
			}),
			cookies: {},
			getClientAddress: () => '203.0.113.10'
		} as Parameters<typeof POST>[0]);

		expect(response.status).toBe(400);
		expect(mockedCheckRateLimit).not.toHaveBeenCalled();
		expect(mockedVerify).not.toHaveBeenCalled();
	});

	it('validates the email and password before checking anything', async () => {
		const response = await POST(postEvent({ email: 'not-an-email', password: '' }));

		expect(response.status).toBe(422);
		expect(mockedCheckRateLimit).not.toHaveBeenCalled();
		expect(mockedVerify).not.toHaveBeenCalled();
	});

	it('rate-limits repeated attempts by a keyed hash of the caller IP, not the raw IP', async () => {
		mockedCheckRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 42 });

		const response = await POST(postEvent({ email: 'owner@example.com', password: 'wrong' }));

		expect(response.status).toBe(429);
		expect(response.headers.get('Retry-After')).toBe('42');
		expect(mockedBucketKey).toHaveBeenCalledWith('203.0.113.10');
		expect(mockedCheckRateLimit).toHaveBeenCalledWith(
			expect.anything(),
			expect.objectContaining({ bucketKey: 'owner_login:hashed-ip' })
		);
		expect(mockedRecordAttempt).toHaveBeenCalledWith('rate_limited');
		expect(mockedVerify).not.toHaveBeenCalled();
	});

	it('rejects incorrect credentials without starting a session', async () => {
		mockedVerify.mockReturnValue(false);

		const response = await POST(postEvent({ email: 'owner@example.com', password: 'wrong' }));

		expect(response.status).toBe(401);
		expect(mockedRecordAttempt).toHaveBeenCalledWith('failed');
		expect(mockedSetSession).not.toHaveBeenCalled();
	});

	it('starts a session and records a sanitized success outcome on correct credentials', async () => {
		mockedVerify.mockReturnValue(true);

		const response = await POST(
			postEvent({ email: 'owner@example.com', password: 'correct-password' })
		);

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ ok: true });
		expect(mockedSetSession).toHaveBeenCalledWith(expect.anything(), 'owner@example.com');
		expect(mockedRecordAttempt).toHaveBeenCalledWith('succeeded');
	});

	it('returns a safe error when owner login is not configured', async () => {
		mockedVerify.mockImplementation(() => {
			throw new Error('SUPER_ADMIN_PASSWORD_HASH is not set');
		});

		const response = await POST(
			postEvent({ email: 'owner@example.com', password: 'correct-password' })
		);

		expect(response.status).toBe(503);
	});

	it('revokes the presented session on logout', async () => {
		const response = await DELETE({ cookies: {} } as Parameters<typeof DELETE>[0]);

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ ok: true });
		expect(mockedClearSession).toHaveBeenCalled();
	});
});
