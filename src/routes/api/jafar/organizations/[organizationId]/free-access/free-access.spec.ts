import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({
	getOwnerSession: vi.fn(),
	consumeOwnerStepUp: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedConsumeStepUp = vi.mocked(consumeOwnerStepUp);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';

function event(body: unknown) {
	return {
		params: { organizationId },
		request: new Request(`http://localhost/api/jafar/organizations/${organizationId}/free-access`, {
			method: 'POST',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

describe('platform owner free-access API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);

		const response = await POST(event({ action: 'end', reason: 'Testing' }));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires a recent password reconfirmation before granting forever access via grant', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(event({ action: 'grant', reason: 'Goodwill gesture' }));

		expect(response.status).toBe(403);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires a recent password reconfirmation before converting to forever access', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(event({ action: 'convert_to_forever', reason: 'Escalation' }));

		expect(response.status).toBe(403);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('does not require reconfirmation for a time-bound grant', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedClient.mockReturnValue({
			from: () => {
				throw new Error('database unavailable in this boundary test');
			}
		} as never);

		const response = await POST(
			event({ action: 'grant', access_until_date: '2026-12-31', reason: 'Trial extension' })
		);

		expect(mockedConsumeStepUp).not.toHaveBeenCalled();
		expect(response.status).toBe(500);
	});

	it('does not require reconfirmation for ending free access', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedClient.mockReturnValue({
			from: () => {
				throw new Error('database unavailable in this boundary test');
			}
		} as never);

		const response = await POST(event({ action: 'end', reason: 'Trial ended' }));

		expect(mockedConsumeStepUp).not.toHaveBeenCalled();
		expect(response.status).toBe(500);
	});
});
