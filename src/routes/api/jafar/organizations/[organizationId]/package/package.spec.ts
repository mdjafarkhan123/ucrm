import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { recordOwnerAccessAudit } from '$lib/server/access/owner';
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
vi.mock('$lib/server/access/owner', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/owner')>(
		'$lib/server/access/owner'
	);
	return { ...actual, recordOwnerAccessAudit: vi.fn() };
});
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedResolveAccess = vi.mocked(resolveOrganizationAccess);
const mockedRecordAudit = vi.mocked(recordOwnerAccessAudit);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';

function event(id: string, body: unknown = { package_key: 'elite' }) {
	return {
		params: { organizationId: id },
		request: new Request('http://localhost/api/jafar/organizations/' + id + '/package', {
			method: 'PATCH',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		cookies: {}
	} as Parameters<typeof PATCH>[0];
}

function accessWith(currentKey: 'starter' | 'growth' | 'elite') {
	return {
		package: { current_key: currentKey, effective_key: currentKey }
	} as never;
}

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

describe('platform owner package change API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);

		const response = await PATCH(event(organizationId));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the organization identifier before database access', async () => {
		mockedOwnerSession.mockReturnValue(session());

		const response = await PATCH(event('not-a-uuid'));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the requested package before database access', async () => {
		mockedOwnerSession.mockReturnValue(session());

		const response = await PATCH(event(organizationId, { package_key: 'ultra' }));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the organization does not exist', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedResolveAccess.mockRejectedValue(new OrganizationAccessNotFoundError());

		const response = await PATCH(event(organizationId));

		expect(response.status).toBe(404);
	});

	it('rejects an upgrade that also carries a future effective date', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedResolveAccess.mockResolvedValue(accessWith('starter'));

		const response = await PATCH(
			event(organizationId, { package_key: 'elite', effective_at: '2099-01-01T00:00:00Z' })
		);

		expect(response.status).toBe(422);
		expect(await response.json()).toEqual({ error: 'Package upgrades take effect immediately.' });
	});

	it('rejects scheduling the package the organization already has', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedResolveAccess.mockResolvedValue(accessWith('growth'));

		const response = await PATCH(
			event(organizationId, { package_key: 'growth', effective_at: '2099-01-01T00:00:00Z' })
		);

		expect(response.status).toBe(422);
		expect(await response.json()).toEqual({ error: 'The current package cannot be scheduled.' });
	});

	it('rejects a downgrade with no future effective date', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedResolveAccess.mockResolvedValue(accessWith('elite'));

		const response = await PATCH(event(organizationId, { package_key: 'starter' }));

		expect(response.status).toBe(422);
		expect(await response.json()).toEqual({
			error: 'Package downgrades require a future effective date.'
		});
	});

	it('returns a safe error when the package update fails', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedResolveAccess.mockResolvedValue(accessWith('starter'));
		mockedClient.mockReturnValue({
			from: () => ({
				update: () => ({
					eq: () => ({
						select: () => ({
							single: async () => ({
								data: null,
								error: { message: 'internal database details' }
							})
						})
					})
				})
			})
		} as never);

		const response = await PATCH(event(organizationId, { package_key: 'elite' }));

		expect(response.status).toBe(500);
		expect(mockedRecordAudit).not.toHaveBeenCalled();
	});

	it('changes the package immediately on an upgrade and records the audit trail', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedResolveAccess.mockResolvedValue(accessWith('starter'));
		const update = vi.fn().mockReturnValue({
			eq: vi.fn().mockReturnValue({
				select: vi.fn().mockReturnValue({
					single: vi.fn().mockResolvedValue({
						data: {
							id: organizationId,
							package_key: 'elite',
							scheduled_package_key: null,
							scheduled_package_effective_at: null,
							updated_at: '2026-08-12T00:00:00Z'
						},
						error: null
					})
				})
			})
		});
		mockedClient.mockReturnValue({ from: () => ({ update }) } as never);

		const response = await PATCH(event(organizationId, { package_key: 'elite' }));

		expect(response.status).toBe(200);
		expect(update).toHaveBeenCalledWith(
			expect.objectContaining({ package_key: 'elite', scheduled_package_key: null })
		);
		expect(mockedRecordAudit).toHaveBeenCalledWith(
			expect.anything(),
			expect.objectContaining({
				organization_id: organizationId,
				event_type: 'package.updated',
				target_type: 'organization.package'
			})
		);
	});

	it('schedules a downgrade for a future date instead of changing the package immediately', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedResolveAccess.mockResolvedValue(accessWith('elite'));
		const update = vi.fn().mockReturnValue({
			eq: vi.fn().mockReturnValue({
				select: vi.fn().mockReturnValue({
					single: vi.fn().mockResolvedValue({
						data: {
							id: organizationId,
							package_key: 'elite',
							scheduled_package_key: 'starter',
							scheduled_package_effective_at: '2099-01-01T00:00:00.000Z',
							updated_at: '2026-08-12T00:00:00Z'
						},
						error: null
					})
				})
			})
		});
		mockedClient.mockReturnValue({ from: () => ({ update }) } as never);

		const response = await PATCH(
			event(organizationId, { package_key: 'starter', effective_at: '2099-01-01T00:00:00Z' })
		);

		expect(response.status).toBe(200);
		expect(update).toHaveBeenCalledWith(
			expect.objectContaining({
				package_key: 'elite',
				scheduled_package_key: 'starter'
			})
		);
	});
});
