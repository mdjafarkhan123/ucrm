import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { POST as publish } from '../publish/+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

function event(body: unknown) {
	return {
		request: new Request('http://localhost/api/jafar/packages/versions', {
			method: 'POST',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		url: new URL('http://localhost/api/jafar/packages/versions'),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

describe('platform owner package version write API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);

		const response = await POST(event({}));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the package version before calling the database', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});

		const response = await POST(event({ package_key: 'growth' }));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('creates a draft through the atomic owner database operation', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		const rpc = vi.fn().mockResolvedValue({ data: 'version-id', error: null });
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await POST(
			event({
				package_key: 'growth',
				display_name: 'Growth',
				public_description: 'For growing teams.',
				value_explanation: 'Includes pipeline tools.',
				price_usd_cents: 14900,
				feature_keys: ['sales.pipeline'],
				limit: { key: 'employee_seats', state: 'numeric', value: 10 }
			})
		);

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ version_id: 'version-id', saved: true });
		expect(rpc).toHaveBeenCalledWith(
			'manage_platform_package_version',
			expect.objectContaining({ operation: 'create_draft', actor_email: 'owner@example.com' })
		);
	});

	it('does not expose raw database errors when saving a draft is rejected', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedClient.mockReturnValue({
			rpc: vi.fn().mockResolvedValue({
			data: null,
			error: { message: 'internal constraint details' }
		})
		} as never);

		const response = await POST(
			event({
				package_key: 'growth',
				display_name: 'Growth',
				public_description: 'For growing teams.',
				price_usd_cents: 14900,
				feature_keys: []
			})
		);

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({
			error: 'The package version could not be saved.'
		});
	});

	it('does not expose raw database errors when publishing is rejected', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedClient.mockReturnValue({
			rpc: vi.fn().mockResolvedValue({
			data: null,
			error: { message: 'internal publication details' }
		})
		} as never);

		const response = await publish(
			event({
				package_key: 'growth',
				version_id: '123e4567-e89b-12d3-a456-426614174000'
			}) as unknown as Parameters<typeof publish>[0]
		);

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({
			error: 'The package version could not be published.'
		});
	});
});
