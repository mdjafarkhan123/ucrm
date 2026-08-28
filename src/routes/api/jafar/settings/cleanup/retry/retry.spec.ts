import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { retryReceiptCleanup } from '$lib/server/jafar/organization-closure-cron';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/jafar/organization-closure-cron', () => ({ retryReceiptCleanup: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedRetry = vi.mocked(retryReceiptCleanup);

const operationId = '123e4567-e89b-12d3-a456-426614174000';

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function postEvent(body: unknown = { operation_id: operationId }) {
	return {
		request: new Request('http://localhost/api/jafar/settings/cleanup/retry', {
			method: 'POST',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

describe('platform owner cleanup retry POST boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue({} as never);
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(postEvent());

		expect(response.status).toBe(401);
		expect(mockedRetry).not.toHaveBeenCalled();
	});

	it('rejects a request missing a valid operation id', async () => {
		const response = await POST(postEvent({ operation_id: 'not-a-uuid' }));

		expect(response.status).toBe(422);
		expect(mockedRetry).not.toHaveBeenCalled();
	});

	it('returns 404 when the deletion receipt was not found', async () => {
		mockedRetry.mockResolvedValue({ found: false, authOk: true, providerOk: true });

		const response = await POST(postEvent());

		expect(response.status).toBe(404);
	});

	it('reports resolved once both external legs finish', async () => {
		mockedRetry.mockResolvedValue({ found: true, authOk: true, providerOk: true });

		const response = await POST(postEvent());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(mockedRetry).toHaveBeenCalledWith(expect.anything(), operationId);
		expect(body).toEqual({ resolved: true });
	});

	it('reports unresolved when a leg is still failing', async () => {
		mockedRetry.mockResolvedValue({ found: true, authOk: false, providerOk: true });

		const response = await POST(postEvent());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body).toEqual({ resolved: false });
	});

	it('returns a 500 when the retry helper throws', async () => {
		mockedRetry.mockRejectedValue(new Error('boom'));

		const response = await POST(postEvent());

		expect(response.status).toBe(500);
	});
});
