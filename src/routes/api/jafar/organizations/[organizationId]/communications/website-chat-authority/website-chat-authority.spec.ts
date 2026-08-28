import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const widgetId = '123e4567-e89b-12d3-a456-426614174001';
const idempotencyKey = '123e4567-e89b-12d3-a456-426614174002';
const url = `http://localhost/api/jafar/organizations/${organizationId}/communications/website-chat-authority`;

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

describe('Website Chat owner authority boundary', () => {
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

	it('loads the bounded authority read model', async () => {
		const client = clientWithRpc([{ data: { widgets: [] }, error: null }]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		const response = await GET(event());
		expect(response.status).toBe(200);
		expect(client.calls[0]).toEqual({
			name: 'get_organization_website_chat_authority',
			args: { p_organization_id: organizationId }
		});
	});

	it('records suspension as the signed-in owner and refreshes health', async () => {
		const client = clientWithRpc([
			{ data: { applied: true }, error: null },
			{ data: { suspension: { reason: 'Abuse review' }, widgets: [] }, error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			event({
				action: 'suspend',
				reason: 'Abuse review',
				idempotency_key: idempotencyKey
			})
		);

		expect(response.status).toBe(200);
		expect(client.calls[0]).toEqual({
			name: 'set_organization_website_chat_suspension',
			args: {
				p_organization_id: organizationId,
				p_engage: true,
				p_reason: 'Abuse review',
				p_actor_email: 'owner@example.com',
				p_idempotency_key: idempotencyKey
			}
		});
		expect(client.calls[1].name).toBe('get_organization_website_chat_authority');
	});

	it('passes token rotation revision and audit evidence to the atomic command', async () => {
		const client = clientWithRpc([
			{ data: { applied: true }, error: null },
			{ data: { suspension: null, widgets: [] }, error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			event({
				action: 'rotate_token',
				widget_id: widgetId,
				expected_revision: 7,
				reason: 'Token appeared in a public support log.',
				idempotency_key: idempotencyKey
			})
		);

		expect(response.status).toBe(200);
		expect(client.calls[0]).toEqual({
			name: 'rotate_website_chat_widget_public_token',
			args: {
				p_organization_id: organizationId,
				p_widget_id: widgetId,
				p_expected_revision: 7,
				p_reason: 'Token appeared in a public support log.',
				p_actor_email: 'owner@example.com',
				p_idempotency_key: idempotencyKey
			}
		});
	});

	it('returns database concurrency conflicts without hiding the reason', async () => {
		const client = clientWithRpc([
			{ data: null, error: { code: '40001', message: 'Reload and try again.' } }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			event({
				action: 'rotate_token',
				widget_id: widgetId,
				expected_revision: 1,
				reason: 'Token appeared in a public support log.',
				idempotency_key: idempotencyKey
			})
		);

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({ error: 'Reload and try again.' });
	});
});
