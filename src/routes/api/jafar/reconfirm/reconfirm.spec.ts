import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession, signOwnerStepUp, verifyOwnerCredentials } from '$lib/server/auth/owner';

vi.mock('$lib/server/auth/owner', () => ({
	getOwnerSession: vi.fn(),
	signOwnerStepUp: vi.fn(),
	verifyOwnerCredentials: vi.fn()
}));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedSignStepUp = vi.mocked(signOwnerStepUp);
const mockedVerifyCredentials = vi.mocked(verifyOwnerCredentials);

function event(body: unknown = { password: 'correct-password' }) {
	return {
		request: new Request('http://localhost/api/jafar/reconfirm', {
			method: 'POST',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

describe('platform owner reconfirm API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);

		const response = await POST(event());

		expect(response.status).toBe(401);
		expect(mockedVerifyCredentials).not.toHaveBeenCalled();
	});

	it('validates the request body before checking the password', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});

		const response = await POST(event({ password: '' }));

		expect(response.status).toBe(422);
		expect(mockedVerifyCredentials).not.toHaveBeenCalled();
	});

	it('rejects an incorrect password without issuing a step-up', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedVerifyCredentials.mockReturnValue(false);

		const response = await POST(event({ password: 'wrong-password' }));

		expect(response.status).toBe(401);
		expect(mockedSignStepUp).not.toHaveBeenCalled();
	});

	it('issues a step-up token for the session email once the password is confirmed', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedVerifyCredentials.mockReturnValue(true);

		const response = await POST(event({ password: 'correct-password' }));

		expect(response.status).toBe(200);
		expect(mockedSignStepUp).toHaveBeenCalledWith(expect.anything(), 'owner@example.com');
	});
});
