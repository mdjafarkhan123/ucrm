import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));

const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedCheckRateLimit = vi.mocked(checkRateLimit);

const token = 'valid-raw-token';

function hourFromNow(hours: number) {
	return new Date(Date.now() + hours * 60 * 60 * 1000).toISOString();
}

function getEvent(searchToken: string | null) {
	const url = new URL('http://localhost/api/setup-password');
	if (searchToken !== null) url.searchParams.set('token', searchToken);
	return { url, getClientAddress: () => '203.0.113.1' } as Parameters<typeof GET>[0];
}

function postEvent(body: unknown) {
	return {
		request: new Request('http://localhost/api/setup-password', {
			method: 'POST',
			body: JSON.stringify(body)
		}),
		getClientAddress: () => '203.0.113.1'
	} as Parameters<typeof POST>[0];
}

type LinkRow = {
	application_id: string;
	administrator_user_id: string;
	intended_email: string;
	expires_at: string;
	consumed_at: string | null;
};

/**
 * Models the atomic consume RPC's actual WHERE-clause behavior (token implicitly matches --
 * there's one link per test -- not consumed, not expired, recipient email matches) including its
 * side effect: a matching call mutates `link.consumed_at`, so a second call against the same
 * mutable `link` object correctly sees it as already used, same as the real single UPDATE would.
 */
function clientWith(link: LinkRow | null) {
	const updateUserById = vi.fn().mockResolvedValue({ error: null });
	const rpc = vi.fn((fnName: string, args: { target_token_hash: string; target_email: string }) => {
		if (fnName !== 'consume_onboarding_application_setup_link')
			throw new Error(`unexpected rpc ${fnName}`);
		const isUsable =
			Boolean(link) && !link!.consumed_at && new Date(link!.expires_at).getTime() > Date.now();
		const matches = isUsable && link!.intended_email === args.target_email;
		if (matches) {
			link!.consumed_at = new Date().toISOString();
			return Promise.resolve({
				data: [
					{
						consumed: true,
						application_id: link!.application_id,
						administrator_user_id: link!.administrator_user_id
					}
				],
				error: null
			});
		}
		return Promise.resolve({
			data: [{ consumed: false, application_id: null, administrator_user_id: null }],
			error: null
		});
	});

	return {
		from: () => ({
			select: () => ({
				eq: () => ({
					maybeSingle: async () => ({ data: link, error: null })
				})
			})
		}),
		auth: { admin: { updateUserById } },
		rpc,
		__updateUserById: updateUserById,
		__rpc: rpc
	};
}

describe('public administrator setup-password API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedCheckRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
	});

	describe('GET', () => {
		it('reports invalid when no token is supplied', async () => {
			const response = await GET(getEvent(null));
			expect(await response.json()).toEqual({ valid: false });
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('returns 429 once the per-IP rate limit is exceeded', async () => {
			mockedClient.mockReturnValue(clientWith(null) as never);
			mockedCheckRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 42 });

			const response = await GET(getEvent(token));
			expect(response.status).toBe(429);
			expect(response.headers.get('Retry-After')).toBe('42');
		});

		it('reports invalid when the token does not match any link', async () => {
			mockedClient.mockReturnValue(clientWith(null) as never);
			const response = await GET(getEvent(token));
			expect(await response.json()).toEqual({ valid: false });
		});

		it('reports invalid when the link is already consumed', async () => {
			mockedClient.mockReturnValue(
				clientWith({
					application_id: 'app-1',
					administrator_user_id: 'admin-1',
					intended_email: 'jordan@ridgeway.example',
					expires_at: hourFromNow(1),
					consumed_at: '2026-08-01T00:00:00Z'
				}) as never
			);
			const response = await GET(getEvent(token));
			expect(await response.json()).toEqual({ valid: false });
		});

		it('reports invalid when the link has expired', async () => {
			mockedClient.mockReturnValue(
				clientWith({
					application_id: 'app-1',
					administrator_user_id: 'admin-1',
					intended_email: 'jordan@ridgeway.example',
					expires_at: hourFromNow(-1),
					consumed_at: null
				}) as never
			);
			const response = await GET(getEvent(token));
			expect(await response.json()).toEqual({ valid: false });
		});

		it('reports a masked email hint when the link is usable', async () => {
			mockedClient.mockReturnValue(
				clientWith({
					application_id: 'app-1',
					administrator_user_id: 'admin-1',
					intended_email: 'jordan@ridgeway.example',
					expires_at: hourFromNow(1),
					consumed_at: null
				}) as never
			);
			const response = await GET(getEvent(token));
			const body = (await response.json()) as { valid: boolean; email_hint: string };
			expect(body.valid).toBe(true);
			expect(body.email_hint).not.toContain('jordan@ridgeway.example');
			expect(body.email_hint).toContain('@ridgeway.example');
		});
	});

	describe('POST', () => {
		it('returns 429 once the per-IP rate limit is exceeded', async () => {
			mockedClient.mockReturnValue(clientWith(null) as never);
			mockedCheckRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 120 });

			const response = await POST(
				postEvent({
					token,
					email: 'jordan@ridgeway.example',
					password: 'longenough1',
					password_confirmation: 'longenough1'
				})
			);
			expect(response.status).toBe(429);
			expect(response.headers.get('Retry-After')).toBe('120');
		});

		it('validates the request body', async () => {
			const response = await POST(
				postEvent({ token, email: 'not-an-email', password: 'short', password_confirmation: 'x' })
			);
			expect(response.status).toBe(422);
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('rejects an invalid or expired token', async () => {
			mockedClient.mockReturnValue(clientWith(null) as never);
			const response = await POST(
				postEvent({
					token,
					email: 'jordan@ridgeway.example',
					password: 'longenough1',
					password_confirmation: 'longenough1'
				})
			);
			expect(response.status).toBe(401);
		});

		it('rejects an email that does not match the intended recipient, and leaves the link usable', async () => {
			const client = clientWith({
				application_id: 'app-1',
				administrator_user_id: 'admin-1',
				intended_email: 'jordan@ridgeway.example',
				expires_at: hourFromNow(1),
				consumed_at: null
			});
			mockedClient.mockReturnValue(client as never);

			const wrongEmailResponse = await POST(
				postEvent({
					token,
					email: 'someone-else@example.com',
					password: 'longenough1',
					password_confirmation: 'longenough1'
				})
			);
			expect(wrongEmailResponse.status).toBe(422);
			expect(client.__updateUserById).not.toHaveBeenCalled();

			// The wrong-email attempt must not have burned the one-time link.
			const correctEmailResponse = await POST(
				postEvent({
					token,
					email: 'jordan@ridgeway.example',
					password: 'longenough1',
					password_confirmation: 'longenough1'
				})
			);
			expect(correctEmailResponse.status).toBe(200);
		});

		it('sets the password and consumes the link on the happy path', async () => {
			const client = clientWith({
				application_id: 'app-1',
				administrator_user_id: 'admin-1',
				intended_email: 'jordan@ridgeway.example',
				expires_at: hourFromNow(1),
				consumed_at: null
			});
			mockedClient.mockReturnValue(client as never);

			const response = await POST(
				postEvent({
					token,
					email: 'jordan@ridgeway.example',
					password: 'longenough1',
					password_confirmation: 'longenough1'
				})
			);
			expect(response.status).toBe(200);
			expect(client.__rpc).toHaveBeenCalledWith('consume_onboarding_application_setup_link', {
				target_token_hash: expect.any(String),
				target_email: 'jordan@ridgeway.example'
			});
			expect(client.__updateUserById).toHaveBeenCalledWith('admin-1', {
				password: 'longenough1'
			});
		});

		it('rejects a second submit once the link has already been consumed, even with the same valid token', async () => {
			const client = clientWith({
				application_id: 'app-1',
				administrator_user_id: 'admin-1',
				intended_email: 'jordan@ridgeway.example',
				expires_at: hourFromNow(1),
				consumed_at: null
			});
			mockedClient.mockReturnValue(client as never);

			const body = {
				token,
				email: 'jordan@ridgeway.example',
				password: 'longenough1',
				password_confirmation: 'longenough1'
			};

			const first = await POST(postEvent(body));
			expect(first.status).toBe(200);

			const second = await POST(postEvent(body));
			expect(second.status).toBe(401);
			expect(client.__updateUserById).toHaveBeenCalledTimes(1);
		});
	});
});
