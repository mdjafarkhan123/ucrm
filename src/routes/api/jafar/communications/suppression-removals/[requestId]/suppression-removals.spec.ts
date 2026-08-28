import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const requestId = '123e4567-e89b-12d3-a456-426614174000';

function event(body?: unknown, id: string = requestId) {
	return {
		params: { requestId: id },
		request: new Request(`http://localhost/api/jafar/communications/suppression-removals/${id}`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: body === undefined ? undefined : JSON.stringify(body)
		}),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function clientWithRpc(results: Array<{ data: unknown; error: unknown }>) {
	const calls: Array<{ name: string; args: unknown }> = [];
	return {
		calls,
		rpc: vi.fn(async (name: string, args: unknown) => {
			calls.push({ name, args });
			return results.shift() ?? { data: null, error: null };
		})
	};
}

describe('owner suppression removal decision boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-1'
		} as never);
	});

	it('refuses a caller without an owner session', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);

		const response = await POST(event({ decision: 'approve' }));

		expect(response.status).toBe(401);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('requires a note to deny, before any database access', async () => {
		const response = await POST(event({ decision: 'deny' }));

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('approves as the signed-in owner and returns the refreshed queue', async () => {
		const client = clientWithRpc([
			{ data: { status: 'approved' }, error: null },
			{ data: { pending: [], pending_total: 0, recently_decided: [] }, error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event({ decision: 'approve' }));

		expect(response.status).toBe(200);
		expect(client.calls[0]).toMatchObject({
			name: 'decide_communication_email_suppression_removal',
			args: { p_request_id: requestId, p_actor_email: 'owner@example.com', p_decision: 'approve' }
		});
		expect(await response.json()).toMatchObject({ pending_total: 0 });
	});

	it('passes a command refusal through as a conflict', async () => {
		const client = clientWithRpc([
			{
				data: null,
				error: { code: '23514', message: 'That removal request has already been decided.' }
			}
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event({ decision: 'approve' }));

		expect(response.status).toBe(409);
		expect(await response.json()).toMatchObject({
			error: 'That removal request has already been decided.'
		});
	});

	it('returns 404 for an unknown request', async () => {
		const client = clientWithRpc([
			{ data: null, error: { code: 'P0002', message: 'That removal request was not found.' } }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event({ decision: 'deny', note: 'no' }));

		expect(response.status).toBe(404);
	});
});
