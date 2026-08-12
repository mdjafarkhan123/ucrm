import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DELETE, POST } from './+server';
import { clearOwnerSession, setOwnerSession, verifyOwnerCredentials } from '$lib/server/auth/owner';

vi.mock('$lib/server/auth/owner', () => ({
	clearOwnerSession: vi.fn(),
	setOwnerSession: vi.fn(),
	verifyOwnerCredentials: vi.fn()
}));

const mockedVerify = vi.mocked(verifyOwnerCredentials);
const mockedSetSession = vi.mocked(setOwnerSession);
const mockedClearSession = vi.mocked(clearOwnerSession);

function postEvent(body: unknown) {
	return {
		request: new Request('http://localhost/api/jafar/session', {
			method: 'POST',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

describe('platform owner session API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects a request body that is not valid JSON', async () => {
		const response = await POST({
			request: new Request('http://localhost/api/jafar/session', {
				method: 'POST',
				body: 'not json',
				headers: { 'content-type': 'application/json' }
			}),
			cookies: {}
		} as Parameters<typeof POST>[0]);

		expect(response.status).toBe(400);
		expect(mockedVerify).not.toHaveBeenCalled();
	});

	it('validates the email and password before checking credentials', async () => {
		const response = await POST(postEvent({ email: 'not-an-email', password: '' }));

		expect(response.status).toBe(422);
		expect(mockedVerify).not.toHaveBeenCalled();
	});

	it('rejects incorrect credentials without starting a session', async () => {
		mockedVerify.mockReturnValue(false);

		const response = await POST(postEvent({ email: 'owner@example.com', password: 'wrong' }));

		expect(response.status).toBe(401);
		expect(mockedSetSession).not.toHaveBeenCalled();
	});

	it('starts a session on correct credentials', async () => {
		mockedVerify.mockReturnValue(true);

		const response = await POST(
			postEvent({ email: 'owner@example.com', password: 'correct-password' })
		);

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ ok: true });
		expect(mockedSetSession).toHaveBeenCalledWith(expect.anything(), 'owner@example.com');
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

	it('clears the session on logout', async () => {
		const response = await DELETE({ cookies: {} } as Parameters<typeof DELETE>[0]);

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ ok: true });
		expect(mockedClearSession).toHaveBeenCalled();
	});
});
