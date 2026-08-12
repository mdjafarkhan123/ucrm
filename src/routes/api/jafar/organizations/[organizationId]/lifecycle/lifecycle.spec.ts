import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({
	getOwnerSession: vi.fn(),
	consumeOwnerStepUp: vi.fn()
}));
vi.mock('$lib/server/access/owner', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/owner')>(
		'$lib/server/access/owner'
	);
	return { ...actual, recordOwnerAccessAudit: vi.fn() };
});
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedConsumeStepUp = vi.mocked(consumeOwnerStepUp);
const mockedRecordAudit = vi.mocked(recordOwnerAccessAudit);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';

function event(id: string, body: unknown = { status: 'suspended' }) {
	return {
		params: { organizationId: id },
		request: new Request('http://localhost/api/jafar/organizations/' + id + '/lifecycle', {
			method: 'PATCH',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		url: new URL('http://localhost/api/jafar/organizations/' + id + '/lifecycle'),
		cookies: {}
	} as Parameters<typeof PATCH>[0];
}

describe('platform owner lifecycle API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);

		const response = await PATCH(event('not-a-uuid'));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the organization identifier before database access', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});

		const response = await PATCH(event('not-a-uuid'));

		expect(response.status).toBe(422);
		expect(await response.json()).toEqual({ error: 'The organization identifier is invalid.' });
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires a recent password reconfirmation before changing status', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await PATCH(event(organizationId));

		expect(response.status).toBe(403);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the organization does not exist', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedConsumeStepUp.mockReturnValue(true);
		mockedClient.mockReturnValue({
			from: () => ({
				select: () => ({
					eq: () => ({ maybeSingle: async () => ({ data: null, error: null }) })
				})
			})
		} as never);

		const response = await PATCH(event(organizationId));

		expect(response.status).toBe(404);
		expect(mockedRecordAudit).not.toHaveBeenCalled();
	});

	it('returns a safe error when the lifecycle update fails', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedConsumeStepUp.mockReturnValue(true);
		const update = vi.fn().mockReturnValue({
			eq: vi.fn().mockReturnValue({
				select: vi.fn().mockReturnValue({
					single: vi.fn().mockResolvedValue({
						data: null,
						error: { message: 'internal database details' }
					})
				})
			})
		});
		mockedClient.mockReturnValue({
			from: (table: string) => {
				if (table === 'organizations') {
					return {
						select: () => ({
							eq: () => ({
								maybeSingle: async () => ({
									data: { id: organizationId, lifecycle_status: 'active' },
									error: null
								})
							})
						}),
						update
					};
				}
				throw new Error(`unexpected table ${table}`);
			}
		} as never);

		const response = await PATCH(event(organizationId));

		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'Organization status could not be changed.' });
		expect(mockedRecordAudit).not.toHaveBeenCalled();
	});

	it('records an audit event with the before and after status on success', async () => {
		mockedOwnerSession.mockReturnValue({
			email: 'owner@example.com',
			expiresAt: Date.now() + 1000
		});
		mockedConsumeStepUp.mockReturnValue(true);
		const client = {
			from: (table: string) => {
				if (table === 'organizations') {
					return {
						select: () => ({
							eq: () => ({
								maybeSingle: async () => ({
									data: { id: organizationId, lifecycle_status: 'active' },
									error: null
								})
							})
						}),
						update: () => ({
							eq: () => ({
								select: () => ({
									single: async () => ({
										data: {
											id: organizationId,
											lifecycle_status: 'suspended',
											updated_at: '2026-08-11T00:00:00Z'
										},
										error: null
									})
								})
							})
						})
					};
				}
				throw new Error(`unexpected table ${table}`);
			}
		};
		mockedClient.mockReturnValue(client as never);

		const response = await PATCH(event(organizationId, { status: 'suspended' }));

		expect(response.status).toBe(200);
		expect(mockedRecordAudit).toHaveBeenCalledWith(
			client,
			expect.objectContaining({
				organization_id: organizationId,
				email: 'owner@example.com',
				event_type: 'organization.lifecycle_changed',
				target_type: 'organization.lifecycle_status',
				before_state: { lifecycle_status: 'active' },
				after_state: { lifecycle_status: 'suspended' }
			})
		);
	});
});
