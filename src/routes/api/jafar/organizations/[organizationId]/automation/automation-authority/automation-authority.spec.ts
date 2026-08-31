import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const idempotencyKey = '123e4567-e89b-12d3-a456-426614174002';
const url = `http://localhost/api/jafar/organizations/${organizationId}/automation/automation-authority`;

function event(body?: unknown, params: Record<string, string> = { organizationId }) {
	return {
		params,
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

describe('Automation owner authority boundary', () => {
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

	it('rejects an invalid organization identifier', async () => {
		const response = await GET(event(undefined, { organizationId: 'not-a-uuid' }));
		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('loads the authority state and the seven limits together', async () => {
		const client = clientWithRpc([
			{ data: { operational_state: 'enabled', security_state: 'active' }, error: null },
			{ data: [], error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		const response = await GET(event());
		expect(response.status).toBe(200);
		expect(client.calls.map((call) => call.name)).toEqual([
			'get_organization_automation_authority',
			'get_organization_automation_limits'
		]);
		expect(client.calls[0].args).toEqual({ p_organization_id: organizationId });
	});

	it('engages an operational disable as the signed-in owner and refreshes', async () => {
		const client = clientWithRpc([
			{ data: { applied: true }, error: null },
			{ data: { operational_state: 'disabled', security_state: 'active' }, error: null },
			{ data: [], error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			event({
				axis: 'operational',
				engage: true,
				reason: 'Investigating suspected abuse.',
				idempotency_key: idempotencyKey
			})
		);

		expect(response.status).toBe(200);
		expect(client.calls[0]).toEqual({
			name: 'set_organization_automation_authority',
			args: {
				p_organization_id: organizationId,
				p_axis: 'operational',
				p_engage: true,
				p_reason: 'Investigating suspected abuse.',
				p_actor_email: 'owner@example.com',
				p_idempotency_key: idempotencyKey
			}
		});
		expect(client.calls[1].name).toBe('get_organization_automation_authority');
	});

	it('engages a security suspension on the independent security axis', async () => {
		const client = clientWithRpc([
			{ data: { applied: true }, error: null },
			{ data: { operational_state: 'enabled', security_state: 'suspended' }, error: null },
			{ data: [], error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			event({
				axis: 'security',
				engage: true,
				reason: 'Security hold pending review.',
				idempotency_key: idempotencyKey
			})
		);

		expect(response.status).toBe(200);
		expect((client.calls[0].args as { p_axis: string }).p_axis).toBe('security');
		expect((client.calls[0].args as { p_engage: boolean }).p_engage).toBe(true);
	});

	it('rejects an unknown authority axis before touching the database', async () => {
		const client = clientWithRpc([]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			event({
				axis: 'billing',
				engage: true,
				reason: 'Not a real axis.',
				idempotency_key: idempotencyKey
			})
		);

		expect(response.status).toBe(422);
		expect(client.calls).toHaveLength(0);
	});

	it('rejects a reason that is too short', async () => {
		const client = clientWithRpc([]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			event({ axis: 'operational', engage: true, reason: 'no', idempotency_key: idempotencyKey })
		);

		expect(response.status).toBe(422);
		expect(client.calls).toHaveLength(0);
	});

	it('returns database concurrency conflicts without hiding the reason', async () => {
		const client = clientWithRpc([
			{ data: null, error: { code: '40001', message: 'Reload and try again.' } }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			event({
				axis: 'operational',
				engage: true,
				reason: 'Investigating suspected abuse.',
				idempotency_key: idempotencyKey
			})
		);

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({ error: 'Reload and try again.' });
	});
});
