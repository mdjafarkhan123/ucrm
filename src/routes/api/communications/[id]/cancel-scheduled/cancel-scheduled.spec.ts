import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedOwnerClient = vi.mocked(getOwnerSupabaseClient);
const mockedRateLimit = vi.mocked(checkRateLimit);
const intentId = '00000000-0000-4000-8000-000000000091';

function event() {
	return {
		params: { id: intentId },
		request: new Request(`http://localhost/api/communications/${intentId}/cancel-scheduled`, {
			method: 'POST'
		})
	} as Parameters<typeof POST>[0];
}

describe('cancelling a scheduled ("Send Later") email', () => {
	const rpc = vi.fn();

	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
			access: { permissions: { 'conversations.send': true }, features: {} }
		} as never);
		mockedOwnerClient.mockReturnValue({ rpc } as never);
		mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		rpc.mockResolvedValue({ data: { id: intentId, status: 'cancelled' }, error: null });
	});

	it('requires conversations.send', async () => {
		await POST(event());
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'conversations.send');
	});

	it('cancels the scheduled message by its intent id', async () => {
		const response = await POST(event());
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('cancel_communication_conversation_reply', {
			target_organization_id: 'org-1',
			target_actor_user_id: 'user-1',
			target_delivery_intent_id: intentId
		});
		expect(await response.json()).toEqual({ intent: { id: intentId, status: 'cancelled' } });
	});

	it('maps a message that already started sending to a 409', async () => {
		rpc.mockResolvedValue({
			data: null,
			error: {
				code: '55000',
				message: 'This message has already started sending and can no longer be cancelled.'
			}
		});
		const response = await POST(event());
		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({
			error: 'This message has already started sending and can no longer be cancelled.',
			reason: 'not_cancellable'
		});
	});

	it('maps a missing message to a 404', async () => {
		rpc.mockResolvedValue({ data: null, error: { code: 'P0002' } });
		const response = await POST(event());
		expect(response.status).toBe(404);
	});

	it('maps a permission failure from the command to a 403', async () => {
		rpc.mockResolvedValue({ data: null, error: { code: '42501' } });
		const response = await POST(event());
		expect(response.status).toBe(403);
		expect(await response.json()).toEqual({
			error: 'You do not have access to do that.',
			reason: 'permission_denied'
		});
	});
});
