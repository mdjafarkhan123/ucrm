import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
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
const packageVersionId = '223e4567-e89b-12d3-a456-426614174000';

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

function event(
	id = organizationId,
	body: unknown = {
		package_version_id: packageVersionId,
		reason: 'Approved commercial change.',
		idempotency_key: 'package-change-123'
	}
) {
	return {
		params: { organizationId: id },
		request: new Request(`http://localhost/api/jafar/organizations/${id}/package`, {
			method: 'PATCH',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		cookies: {}
	} as Parameters<typeof PATCH>[0];
}

describe('platform owner package change API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockReturnValue(session());
		mockedResolveAccess.mockResolvedValue({} as never);
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);
		const response = await PATCH(event());
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the organization and package command before database access', async () => {
		expect((await PATCH(event('not-a-uuid'))).status).toBe(422);
		expect((await PATCH(event(organizationId, { package_version_id: 'bad' }))).status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns not found when the access projection cannot find the organization', async () => {
		mockedResolveAccess.mockRejectedValue(new OrganizationAccessNotFoundError());
		const rpc = vi.fn().mockResolvedValue({ data: { applied: true }, error: null });
		mockedClient.mockReturnValue({ rpc } as never);
		const response = await PATCH(event());
		expect(response.status).toBe(404);
	});

	it('passes the published version, reason, actor, and idempotency key to the atomic command', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { applied: true }, error: null });
		mockedClient.mockReturnValue({ rpc } as never);
		const response = await PATCH(event());
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('apply_organization_package_change', {
			target_organization_id: organizationId,
			target_package_version_id: packageVersionId,
			idempotency_key: 'package-change-123',
			private_reason: 'Approved commercial change.',
			actor_owner_email: 'owner@example.com'
		});
	});

	it('maps database validation and serialization conflicts to a safe conflict response', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: null, error: { code: '23514', message: 'private details' } });
		mockedClient.mockReturnValue({ rpc } as never);
		const response = await PATCH(event());
		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({ error: 'private details' });
	});
});
