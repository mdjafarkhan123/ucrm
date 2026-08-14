import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DELETE, PUT } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	OrganizationAccessNotFoundError,
	resolveOrganizationAccess
} from '$lib/server/access/effective';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/access/effective', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/effective')>(
		'$lib/server/access/effective'
	);
	return { ...actual, resolveOrganizationAccess: vi.fn() };
});
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedResolveAccess = vi.mocked(resolveOrganizationAccess);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const featureKey = 'communications.inbox';

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

function event(
	handler: typeof PUT | typeof DELETE,
	body: unknown = {
		override_state: 'on',
		starts_at: '2026-08-14T00:00:00Z',
		reason: 'Approved support exception.',
		idempotency_key: 'feature-change-123'
	}
) {
	return {
		params: { organizationId, featureKey },
		request: new Request('http://localhost/api/jafar/organizations/id/feature-overrides/key', {
			method: handler === DELETE ? 'DELETE' : 'PUT',
			body: handler === DELETE ? undefined : JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		cookies: {}
	} as Parameters<typeof PUT>[0];
}

describe('platform owner feature exception API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockReturnValue(session());
		mockedResolveAccess.mockResolvedValue({} as never);
	});

	it('requires owner authentication for both mutation and legacy delete attempts', async () => {
		mockedOwnerSession.mockReturnValue(null);
		expect((await PUT(event(PUT))).status).toBe(401);
		expect((await DELETE(event(DELETE))).status).toBe(401);
	});

	it('requires a reason, start time, and idempotency key', async () => {
		const response = await PUT(event(PUT, { override_state: 'on' }));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects expiry at or before the explicit start', async () => {
		const response = await PUT(
			event(PUT, {
				override_state: 'on',
				starts_at: '2026-08-14T00:00:00Z',
				expires_at: '2026-08-13T00:00:00Z',
				reason: 'Reason.',
				idempotency_key: 'feature-change-123'
			})
		);
		expect(response.status).toBe(422);
	});

	it('calls the atomic feature command and returns resolved access', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { applied: true }, error: null });
		mockedClient.mockReturnValue({ rpc } as never);
		const response = await PUT(event(PUT));
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith(
			'apply_organization_feature_exception',
			expect.objectContaining({
				target_organization_id: organizationId,
				target_feature_key: featureKey,
				target_override_state: 'on',
				private_reason: 'Approved support exception.',
				actor_owner_email: 'owner@example.com'
			})
		);
	});

	it('maps a missing organization and refuses history-destructive delete', async () => {
		mockedResolveAccess.mockRejectedValue(new OrganizationAccessNotFoundError());
		const rpc = vi.fn().mockResolvedValue({ data: { applied: true }, error: null });
		mockedClient.mockReturnValue({ rpc } as never);
		expect((await PUT(event(PUT))).status).toBe(404);
		expect((await DELETE(event(DELETE))).status).toBe(405);
	});
});
