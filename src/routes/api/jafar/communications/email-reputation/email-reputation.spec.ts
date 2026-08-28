import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const url = 'http://localhost/api/jafar/communications/email-reputation';

function event(body?: unknown) {
	return {
		params: {},
		request: new Request(url, {
			method: body === undefined ? 'GET' : 'POST',
			headers: { 'content-type': 'application/json' },
			body: body === undefined ? undefined : JSON.stringify(body)
		}),
		url: new URL(url),
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

const validChange = {
	signal: 'complaint',
	window_key: 'rolling_24h',
	warn_rate: 0.04,
	pause_rate: 0.08,
	reason: 'tightening after a provider warning',
	confirm_platform_change: true
};

describe('owner email reputation boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-1'
		});
	});

	it('refuses a caller without an owner session', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);

		const response = await GET(event());

		expect(response.status).toBe(401);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('rejects an invalid threshold before touching the database', async () => {
		const response = await POST(event({ ...validChange, signal: 'bounced', reason: 'x' }));

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('sends the change as the signed-in owner and returns the refreshed overview', async () => {
		const client = clientWithRpc([
			{ data: { organization_overrides_affected: 2 }, error: null },
			{ data: { platform_thresholds: [], attention: [] }, error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event(validChange));

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({
			result: { organization_overrides_affected: 2 }
		});
		expect(client.calls[0]).toMatchObject({
			name: 'set_communication_email_reputation_threshold',
			args: {
				p_scope: 'platform',
				p_organization_id: null,
				p_actor_email: 'owner@example.com',
				p_confirm_platform_change: true
			}
		});
	});

	it('passes the command refusal through as a conflict', async () => {
		const client = clientWithRpc([
			{
				data: null,
				error: { code: '23514', message: 'Changing the platform ceiling needs confirmation.' }
			}
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event({ ...validChange, confirm_platform_change: false }));

		expect(response.status).toBe(409);
		expect(await response.json()).toMatchObject({
			error: 'Changing the platform ceiling needs confirmation.'
		});
	});
});
