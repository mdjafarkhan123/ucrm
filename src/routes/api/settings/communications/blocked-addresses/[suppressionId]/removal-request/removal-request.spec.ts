import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DELETE, POST } from './+server';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/access/permission', () => ({ requireOrganizationAdmin: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const userId = '123e4567-e89b-12d3-a456-426614174001';
const suppressionId = '123e4567-e89b-12d3-a456-426614174002';

function event(method: 'POST' | 'DELETE', body?: unknown, id: string = suppressionId) {
	return {
		params: { suppressionId: id },
		request: new Request(
			`http://localhost/api/settings/communications/blocked-addresses/${id}/removal-request`,
			{
				method,
				headers: { 'content-type': 'application/json' },
				body: body === undefined ? undefined : JSON.stringify(body)
			}
		)
	} as Parameters<typeof POST>[0];
}

const validBody = {
	reason: 'the address was corrected',
	evidence: 'confirmed by phone with the customer',
	consent_confirmed: true
};

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

describe('contractor suppression removal request API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(requireOrganizationAdmin).mockResolvedValue({
			auth: {
				user: { id: userId, email: 'admin@ridgeway.example' },
				organization: { id: organizationId, name: 'Ridgeway', role: 'admin' }
			},
			access: { features: {}, limits: {}, permissions: {} }
		} as never);
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
	});

	it('refuses a non-administrator before any database access', async () => {
		vi.mocked(requireOrganizationAdmin).mockResolvedValue({
			response: new Response(null, { status: 403 })
		});

		const response = await POST(event('POST', validBody));

		expect(response.status).toBe(403);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('rejects a request with no consent confirmation before service-role access', async () => {
		const response = await POST(event('POST', { ...validBody, consent_confirmed: false }));

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('rejects a non-uuid suppression id', async () => {
		const response = await POST(event('POST', validBody, 'not-a-uuid'));

		expect(response.status).toBe(404);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('files the request as the signed-in administrator and returns the refreshed list', async () => {
		const client = clientWithRpc([
			{ data: { status: 'pending', suppression_reason: 'complaint' }, error: null },
			{ data: { blocked: [], blocked_total: 0, recently_cleared: [] }, error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event('POST', validBody));

		expect(response.status).toBe(200);
		expect(client.calls[0]).toMatchObject({
			name: 'request_communication_email_suppression_removal',
			args: {
				p_organization_id: organizationId,
				p_suppression_id: suppressionId,
				p_actor_user_id: userId,
				p_actor_email: 'admin@ridgeway.example'
			}
		});
		expect(await response.json()).toMatchObject({ blocked_total: 0 });
	});

	it('passes a command refusal through as a conflict', async () => {
		const client = clientWithRpc([
			{ data: null, error: { code: '23514', message: 'That address is no longer blocked.' } }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(event('POST', validBody));

		expect(response.status).toBe(409);
		expect(await response.json()).toMatchObject({ error: 'That address is no longer blocked.' });
	});

	it('withdraws a pending request through the withdraw command', async () => {
		const client = clientWithRpc([
			{ data: { status: 'withdrawn' }, error: null },
			{ data: { blocked: [], blocked_total: 0, recently_cleared: [] }, error: null }
		]);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await DELETE(event('DELETE'));

		expect(response.status).toBe(200);
		expect(client.calls[0]).toMatchObject({
			name: 'withdraw_communication_email_suppression_removal',
			args: { p_organization_id: organizationId, p_suppression_id: suppressionId }
		});
	});
});
