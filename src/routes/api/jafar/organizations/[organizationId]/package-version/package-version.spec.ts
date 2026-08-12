import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/access/owner', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/owner')>(
		'$lib/server/access/owner'
	);
	return { ...actual, recordOwnerAccessAudit: vi.fn() };
});
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedRecordAudit = vi.mocked(recordOwnerAccessAudit);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const packageVersionId = '223e4567-e89b-12d3-a456-426614174000';

const validBody = {
	package_version_id: packageVersionId,
	paid_through_date: '2026-12-31',
	reason: 'Legacy contract carried over from the old system.'
};

function event(id: string, body: unknown = validBody) {
	return {
		params: { organizationId: id },
		request: new Request('http://localhost/api/jafar/organizations/' + id + '/package-version', {
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

describe('platform owner legacy package assignment API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);

		const response = await POST(event(organizationId));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the organization identifier before database access', async () => {
		mockedOwnerSession.mockReturnValue(session());

		const response = await POST(event('not-a-uuid'));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the assignment body before database access', async () => {
		mockedOwnerSession.mockReturnValue(session());

		const response = await POST(event(organizationId, { ...validBody, reason: '' }));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns a conflict when the database rejects a duplicate assignment', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue({
			rpc: vi.fn().mockResolvedValue({ error: { code: '23505', message: 'duplicate' } })
		} as never);

		const response = await POST(event(organizationId));

		expect(response.status).toBe(409);
		expect(mockedRecordAudit).not.toHaveBeenCalled();
	});

	it('returns a server error for unexpected database failures', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue({
			rpc: vi
				.fn()
				.mockResolvedValue({ error: { code: '55000', message: 'internal database details' } })
		} as never);

		const response = await POST(event(organizationId));

		expect(response.status).toBe(500);
	});

	it('assigns the legacy package and records the audit trail on success', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const rpc = vi.fn().mockResolvedValue({ error: null });
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await POST(event(organizationId));

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ organization_id: organizationId, assigned: true });
		expect(rpc).toHaveBeenCalledWith('record_legacy_organization_package', {
			target_organization_id: organizationId,
			target_package_version_id: packageVersionId,
			target_paid_through_date: '2026-12-31',
			target_reason: validBody.reason
		});
		expect(mockedRecordAudit).toHaveBeenCalledWith(
			expect.anything(),
			expect.objectContaining({
				organization_id: organizationId,
				event_type: 'package.legacy_assigned',
				target_type: 'organization.package_version',
				target_key: packageVersionId
			})
		);
	});
});
