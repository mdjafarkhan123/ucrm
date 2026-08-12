import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const packageKey = 'growth';

function event(body: unknown = { package_key: packageKey }) {
	return {
		request: new Request('http://localhost/api/jafar/packages/retire', {
			method: 'POST',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

describe('platform owner package retire API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);

		const response = await POST(event());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the package selection before calling the database', async () => {
		mockedOwnerSession.mockReturnValue(session());

		const response = await POST(event({ package_key: 'ultra' }));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('surfaces the guard message when retirement is rejected', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue({
			rpc: vi.fn().mockResolvedValue({
				data: null,
				error: { message: 'Package is still assigned to an organization.' }
			})
		} as never);

		const response = await POST(event());

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({
			error: 'Package is still assigned to an organization.'
		});
	});

	it('retires the package through the atomic owner database operation', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const rpc = vi.fn().mockResolvedValue({ data: 'package-id', error: null });
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await POST(event());

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ package_id: 'package-id', retired: true });
		expect(rpc).toHaveBeenCalledWith('manage_platform_package_version', {
			operation: 'retire',
			target_package_key: packageKey,
			actor_email: 'owner@example.com'
		});
	});
});
