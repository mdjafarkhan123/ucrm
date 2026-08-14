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
const limitKey = 'employee_seats';

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

function event(
	handler: typeof PUT | typeof DELETE,
	body: unknown = {
		override_state: 'numeric',
		limit_value: 12,
		starts_at: '2026-08-14T00:00:00Z',
		reason: 'Approved seat exception.',
		idempotency_key: 'limit-change-123'
	}
) {
	return {
		params: { organizationId, limitKey },
		request: new Request('http://localhost/api/jafar/organizations/id/limit-overrides/key', {
			method: handler === DELETE ? 'DELETE' : 'PUT',
			body: handler === DELETE ? undefined : JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		cookies: {}
	} as Parameters<typeof PUT>[0];
}

describe('platform owner limit exception API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockReturnValue(session());
		mockedResolveAccess.mockResolvedValue({} as never);
	});

	it('requires owner authentication and validates the limit state', async () => {
		mockedOwnerSession.mockReturnValue(null);
		expect((await PUT(event(PUT))).status).toBe(401);
		expect((await DELETE(event(DELETE))).status).toBe(401);
		mockedOwnerSession.mockReturnValue(session());
		expect(
			(
				await PUT(
					event(PUT, {
						override_state: 'numeric',
						starts_at: '2026-08-14T00:00:00Z',
						reason: 'Reason.'
					})
				)
			).status
		).toBe(422);
	});

	it('distinguishes numeric, not included, and unlimited states before the database', async () => {
		const response = await PUT(
			event(PUT, {
				override_state: 'unlimited',
				limit_value: 1,
				starts_at: '2026-08-14T00:00:00Z',
				reason: 'Reason.',
				idempotency_key: 'limit-change-123'
			})
		);
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('calls the atomic limit command with the explicit state and reason', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { applied: true }, error: null });
		mockedClient.mockReturnValue({ rpc } as never);
		const response = await PUT(event(PUT));
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith(
			'apply_organization_limit_exception',
			expect.objectContaining({
				target_organization_id: organizationId,
				target_limit_key: limitKey,
				target_limit_state: 'numeric',
				target_limit_value: 12,
				private_reason: 'Approved seat exception.',
				actor_owner_email: 'owner@example.com'
			})
		);
	});

	it('returns not found and prevents history-destructive delete', async () => {
		mockedResolveAccess.mockRejectedValue(new OrganizationAccessNotFoundError());
		const rpc = vi.fn().mockResolvedValue({ data: { applied: true }, error: null });
		mockedClient.mockReturnValue({ rpc } as never);
		expect((await PUT(event(PUT))).status).toBe(404);
		expect((await DELETE(event(DELETE))).status).toBe(405);
	});
});
