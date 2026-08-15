import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const prospectId = '123e4567-e89b-12d3-a456-426614174000';

function event(id: string, body: unknown = {}) {
	return {
		params: { prospectId: id },
		request: new Request('http://localhost/api/jafar/prospects/' + id + '/not-proceeding', {
			method: 'POST',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		url: new URL('http://localhost/api/jafar/prospects/' + id + '/not-proceeding'),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function clientWith(rpcError: { message: string } | null = null) {
	const rpc = vi.fn().mockResolvedValue({ error: rpcError });
	return { rpc, __rpc: rpc };
}

describe('platform owner prospect not-proceeding API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const response = await POST(event(prospectId));
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the prospect identifier before database access', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const response = await POST(event('not-a-uuid'));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the prospect does not exist', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue(
			clientWith({ message: 'The onboarding application does not exist.' }) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(404);
	});

	it('rejects marking an already-paid application not proceeding', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue(
			clientWith({ message: 'Only an unpaid application can be marked not proceeding.' }) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
	});

	it('marks an unpaid application not proceeding with no reason', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = clientWith();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(200);
		expect(client.__rpc).toHaveBeenCalledWith('mark_onboarding_application_not_proceeding', {
			target_application_id: prospectId,
			actor_email: 'owner@example.com',
			reason: undefined
		});
	});

	it('passes a supplied reason through to close a possible duplicate', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = clientWith();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(prospectId, { reason: 'Same business, different form fill.' }));
		expect(response.status).toBe(200);
		expect(client.__rpc).toHaveBeenCalledWith('mark_onboarding_application_not_proceeding', {
			target_application_id: prospectId,
			actor_email: 'owner@example.com',
			reason: 'Same business, different form fill.'
		});
	});

	it('returns 422 with a field error when closing an unacknowledged duplicate without a reason', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue(
			clientWith({ message: 'A private reason is required to close a possible duplicate.' }) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.reason).toBeDefined();
	});

	it('returns a safe server error when the update fails', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue(clientWith({ message: 'internal database details' }) as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'The application could not be updated.' });
	});
});
