import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const packageKey = 'growth';
const versionId = '123e4567-e89b-12d3-a456-426614174000';

function event(body: unknown = { package_key: packageKey, version_id: versionId }) {
	return {
		request: new Request('http://localhost/api/jafar/packages/publish', {
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

describe('platform owner package publish API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);

		const response = await POST(event());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the draft selection before calling the database', async () => {
		mockedOwnerSession.mockReturnValue(session());

		const response = await POST(event({ package_key: packageKey }));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('does not expose raw database errors when publication is rejected', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue({
			rpc: vi
				.fn()
				.mockResolvedValue({ data: null, error: { message: 'internal constraint details' } })
		} as never);

		const response = await POST(event());

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({
			error: 'The package version could not be published.'
		});
	});

	it('publishes the draft version through the atomic owner database operation', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const rpc = vi.fn().mockResolvedValue({ data: versionId, error: null });
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await POST(event());

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ version_id: versionId, published: true });
		expect(rpc).toHaveBeenCalledWith('manage_platform_package_version', {
			operation: 'publish',
			target_package_key: packageKey,
			target_version_id: versionId,
			actor_email: 'owner@example.com'
		});
	});
});
