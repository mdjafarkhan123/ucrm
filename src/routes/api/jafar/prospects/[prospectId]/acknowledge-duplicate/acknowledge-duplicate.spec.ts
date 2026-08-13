import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const prospectId = '123e4567-e89b-12d3-a456-426614174000';

function event(id: string) {
	return {
		params: { prospectId: id },
		request: new Request('http://localhost/api/jafar/prospects/' + id + '/acknowledge-duplicate', {
			method: 'POST'
		}),
		url: new URL('http://localhost/api/jafar/prospects/' + id + '/acknowledge-duplicate'),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

function clientWith(rpcError: { message: string } | null = null) {
	const rpc = vi.fn().mockResolvedValue({ error: rpcError });
	return { rpc, __rpc: rpc };
}

describe('platform owner prospect acknowledge-duplicate API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);
		const response = await POST(event(prospectId));
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the prospect identifier before database access', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const response = await POST(event('not-a-uuid'));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the prospect does not exist', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({ message: 'The onboarding application does not exist.' }) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(404);
	});

	it('rejects acknowledging an application that was never flagged as a duplicate', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				message: 'This application was not flagged as a possible duplicate.'
			}) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
	});

	it('rejects acknowledging an already-acknowledged duplicate', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({ message: 'This possible duplicate was already acknowledged.' }) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
	});

	it('rejects acknowledging once the application is past the unpaid stages', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				message: 'Only an unpaid application can have its duplicate flag acknowledged.'
			}) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
	});

	it('acknowledges a possible duplicate', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const client = clientWith();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(200);
		expect(client.__rpc).toHaveBeenCalledWith('acknowledge_onboarding_application_duplicate', {
			target_application_id: prospectId,
			actor_email: 'owner@example.com'
		});
	});

	it('returns a safe server error when the update fails', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(clientWith({ message: 'internal database details' }) as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'The application could not be updated.' });
	});
});
