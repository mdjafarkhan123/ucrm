import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
	clearOwnerSession,
	getOwnerSession,
	ownerLoginRateLimitBucketKey,
	setOwnerSession
} from './owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/env', () => ({
	getServerEnv: () => ({
		SUPABASE_SERVICE_ROLE_KEY: 'service-role-key',
		SUPER_ADMIN_EMAIL: 'owner@example.com',
		SUPER_ADMIN_PASSWORD_HASH: 'hash',
		SESSION_SECRET: 'secret'
	})
}));

const mockedClient = vi.mocked(getOwnerSupabaseClient);

const VALID_SESSION_ID = '11111111-1111-1111-1111-111111111111';

function cookieJar() {
	const store = new Map<string, string>();
	return {
		get: (name: string) => store.get(name),
		set: (name: string, value: string) => void store.set(name, value),
		delete: (name: string) => void store.delete(name),
		_store: store
	};
}

function fakeEvent(cookies: ReturnType<typeof cookieJar>) {
	return { cookies, url: new URL('https://app.example.com/jafar') } as never;
}

/** Signs a session id exactly the way owner.ts does, so tests can hand it a cookie without exporting internals. */
async function signSessionIdForTest(sessionId: string) {
	const cookies = cookieJar();
	mockedClient.mockReturnValue({
		from: () => ({
			update: () => ({ eq: () => ({ is: async () => ({ error: null }) }) }),
			insert: () => ({
				select: () => ({ single: async () => ({ data: { id: sessionId }, error: null }) })
			})
		})
	} as never);
	await setOwnerSession(fakeEvent(cookies), 'owner@example.com');
	return cookies.get('jafar_session')!;
}

describe('owner session registry seam', () => {
	beforeEach(() => vi.clearAllMocks());

	describe('getOwnerSession', () => {
		it('returns null when no cookie is present', async () => {
			const session = await getOwnerSession(fakeEvent(cookieJar()));
			expect(session).toBeNull();
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('returns null when the cookie signature is invalid', async () => {
			const cookies = cookieJar();
			cookies.set('jafar_session', `${VALID_SESSION_ID}.not-a-real-signature`);

			const session = await getOwnerSession(fakeEvent(cookies));
			expect(session).toBeNull();
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('returns null when the session id is not a well-formed uuid, even if trivially signed', async () => {
			const cookies = cookieJar();
			cookies.set('jafar_session', 'not-a-uuid.somesignature');

			const session = await getOwnerSession(fakeEvent(cookies));
			expect(session).toBeNull();
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('returns the session when the registry has an unrevoked, unexpired row', async () => {
			const cookieValue = await signSessionIdForTest(VALID_SESSION_ID);
			const cookies = cookieJar();
			cookies.set('jafar_session', cookieValue);

			mockedClient.mockReturnValue({
				from: () => ({
					select: () => ({
						eq: () => ({
							maybeSingle: async () => ({
								data: {
									owner_email: 'owner@example.com',
									expires_at: new Date(Date.now() + 60_000).toISOString(),
									revoked_at: null
								},
								error: null
							})
						})
					})
				})
			} as never);

			const session = await getOwnerSession(fakeEvent(cookies));
			expect(session).toEqual({ email: 'owner@example.com', sessionId: VALID_SESSION_ID });
		});

		it('rejects a revoked session', async () => {
			const cookieValue = await signSessionIdForTest(VALID_SESSION_ID);
			const cookies = cookieJar();
			cookies.set('jafar_session', cookieValue);

			mockedClient.mockReturnValue({
				from: () => ({
					select: () => ({
						eq: () => ({
							maybeSingle: async () => ({
								data: {
									owner_email: 'owner@example.com',
									expires_at: new Date(Date.now() + 60_000).toISOString(),
									revoked_at: new Date().toISOString()
								},
								error: null
							})
						})
					})
				})
			} as never);

			expect(await getOwnerSession(fakeEvent(cookies))).toBeNull();
		});

		it('rejects an expired session', async () => {
			const cookieValue = await signSessionIdForTest(VALID_SESSION_ID);
			const cookies = cookieJar();
			cookies.set('jafar_session', cookieValue);

			mockedClient.mockReturnValue({
				from: () => ({
					select: () => ({
						eq: () => ({
							maybeSingle: async () => ({
								data: {
									owner_email: 'owner@example.com',
									expires_at: new Date(Date.now() - 1_000).toISOString(),
									revoked_at: null
								},
								error: null
							})
						})
					})
				})
			} as never);

			expect(await getOwnerSession(fakeEvent(cookies))).toBeNull();
		});

		it('fails closed when the registry lookup errors', async () => {
			const cookieValue = await signSessionIdForTest(VALID_SESSION_ID);
			const cookies = cookieJar();
			cookies.set('jafar_session', cookieValue);

			mockedClient.mockReturnValue({
				from: () => ({
					select: () => ({
						eq: () => ({
							maybeSingle: async () => {
								throw new Error('the database is unreachable');
							}
						})
					})
				})
			} as never);

			expect(await getOwnerSession(fakeEvent(cookies))).toBeNull();
		});
	});

	describe('setOwnerSession', () => {
		it('rotates out a previously presented session before issuing a new one', async () => {
			const previousCookieValue = await signSessionIdForTest('22222222-2222-2222-2222-222222222222');
			const cookies = cookieJar();
			cookies.set('jafar_session', previousCookieValue);

			const updateEq = vi.fn(() => ({ is: vi.fn(async () => ({ error: null })) }));
			const update = vi.fn(() => ({ eq: updateEq }));
			const insertSingle = vi.fn(async () => ({ data: { id: VALID_SESSION_ID }, error: null }));
			const insert = vi.fn(() => ({ select: () => ({ single: insertSingle }) }));
			mockedClient.mockReturnValue({ from: () => ({ update, insert }) } as never);

			await setOwnerSession(fakeEvent(cookies), 'owner@example.com');

			expect(update).toHaveBeenCalledWith(
				expect.objectContaining({ revoked_reason: 'rotated', revoked_at: expect.any(String) })
			);
			expect(updateEq).toHaveBeenCalledWith('id', '22222222-2222-2222-2222-222222222222');
			expect(insert).toHaveBeenCalledWith(
				expect.objectContaining({ owner_email: 'owner@example.com' })
			);
			expect(cookies.get('jafar_session')).toContain(VALID_SESSION_ID);
		});

		it('issues a session with no rotation when no cookie was presented', async () => {
			const cookies = cookieJar();
			const update = vi.fn();
			const insertSingle = vi.fn(async () => ({ data: { id: VALID_SESSION_ID }, error: null }));
			const insert = vi.fn(() => ({ select: () => ({ single: insertSingle }) }));
			mockedClient.mockReturnValue({ from: () => ({ update, insert }) } as never);

			await setOwnerSession(fakeEvent(cookies), 'owner@example.com');

			expect(update).not.toHaveBeenCalled();
			expect(insert).toHaveBeenCalled();
		});
	});

	describe('clearOwnerSession', () => {
		it('revokes the presented session with reason logout and clears the cookie', async () => {
			const cookieValue = await signSessionIdForTest(VALID_SESSION_ID);
			const cookies = cookieJar();
			cookies.set('jafar_session', cookieValue);

			const updateEq = vi.fn(() => ({ is: vi.fn(async () => ({ error: null })) }));
			const update = vi.fn(() => ({ eq: updateEq }));
			mockedClient.mockReturnValue({ from: () => ({ update }) } as never);

			await clearOwnerSession(fakeEvent(cookies));

			expect(update).toHaveBeenCalledWith(
				expect.objectContaining({ revoked_reason: 'logout' })
			);
			expect(updateEq).toHaveBeenCalledWith('id', VALID_SESSION_ID);
			expect(cookies.get('jafar_session')).toBeUndefined();
		});

		it('does nothing when no cookie is presented', async () => {
			const cookies = cookieJar();

			await clearOwnerSession(fakeEvent(cookies));

			expect(mockedClient).not.toHaveBeenCalled();
		});
	});

	describe('ownerLoginRateLimitBucketKey', () => {
		it('never contains the raw IP address', () => {
			const key = ownerLoginRateLimitBucketKey('198.51.100.7');
			expect(key).not.toContain('198.51.100.7');
			expect(key.startsWith('owner_login:')).toBe(true);
		});

		it('is deterministic for the same IP so repeated attempts share a bucket', () => {
			expect(ownerLoginRateLimitBucketKey('198.51.100.7')).toBe(
				ownerLoginRateLimitBucketKey('198.51.100.7')
			);
		});

		it('differs for different IPs', () => {
			expect(ownerLoginRateLimitBucketKey('198.51.100.7')).not.toBe(
				ownerLoginRateLimitBucketKey('198.51.100.8')
			);
		});
	});
});
