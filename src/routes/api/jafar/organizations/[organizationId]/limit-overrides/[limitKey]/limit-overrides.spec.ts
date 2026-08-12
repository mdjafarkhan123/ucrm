import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DELETE, PUT } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	OrganizationAccessNotFoundError,
	resolveOrganizationAccess
} from '$lib/server/access/effective';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/access/effective', () => ({
	OrganizationAccessNotFoundError: class OrganizationAccessNotFoundError extends Error {},
	resolveOrganizationAccess: vi.fn()
}));
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
const limitKey = 'employee_seats';

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

function putEvent(
	id: string,
	key: string,
	body: unknown = { override_state: 'on', limit_value: 25 }
) {
	return {
		params: { organizationId: id, limitKey: key },
		request: new Request(`http://localhost/api/jafar/organizations/${id}/limit-overrides/${key}`, {
			method: 'PUT',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		cookies: {}
	} as Parameters<typeof PUT>[0];
}

function deleteEvent(id: string, key: string) {
	return {
		params: { organizationId: id, limitKey: key },
		cookies: {}
	} as Parameters<typeof DELETE>[0];
}

function clientWith(options: {
	before?: unknown;
	upsertResult?: { data?: unknown; error?: { message: string } | null };
	deleteResult?: { error: { message: string } | null };
}) {
	const upsert = vi.fn().mockReturnValue({
		select: () => ({
			single: async () =>
				options.upsertResult ?? {
					data: {
						limit_key: limitKey,
						limit_value: 25,
						is_unlimited: false,
						starts_at: '2026-08-12T00:00:00.000Z',
						expires_at: null,
						updated_at: '2026-08-12T00:00:00.000Z'
					},
					error: null
				}
		})
	});
	const del = vi.fn().mockResolvedValue(options.deleteResult ?? { error: null });
	return {
		from: (table: string) => {
			if (table === 'organization_limit_overrides') {
				return {
					select: () => ({
						eq: () => ({
							eq: () => ({
								maybeSingle: async () => ({ data: options.before ?? null, error: null })
							})
						})
					}),
					upsert,
					delete: () => ({ eq: () => ({ eq: del }) })
				};
			}
			throw new Error(`unexpected table ${table}`);
		},
		__upsert: upsert,
		__delete: del
	};
}

describe('platform owner limit override API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	describe('PUT', () => {
		it('rejects callers without the separate owner session', async () => {
			mockedOwnerSession.mockReturnValue(null);

			const response = await PUT(putEvent(organizationId, limitKey));

			expect(response.status).toBe(401);
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('validates the organization and limit identifiers', async () => {
			mockedOwnerSession.mockReturnValue(session());

			const response = await PUT(putEvent(organizationId, 'not-a-real-limit'));

			expect(response.status).toBe(422);
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('requires a numeric limit or the unlimited flag', async () => {
			mockedOwnerSession.mockReturnValue(session());

			const response = await PUT(
				putEvent(organizationId, limitKey, { override_state: 'on', limit_value: null })
			);

			expect(response.status).toBe(422);
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('returns 404 when the organization does not exist', async () => {
			mockedOwnerSession.mockReturnValue(session());
			mockedResolveAccess.mockRejectedValue(new OrganizationAccessNotFoundError());

			const response = await PUT(putEvent(organizationId, limitKey));

			expect(response.status).toBe(404);
		});

		it('rejects an expiry that is not later than the start time', async () => {
			mockedOwnerSession.mockReturnValue(session());

			const response = await PUT(
				putEvent(organizationId, limitKey, {
					override_state: 'on',
					limit_value: 25,
					starts_at: '2026-08-12T00:00:00.000Z',
					expires_at: '2026-08-12T00:00:00.000Z'
				})
			);

			expect(response.status).toBe(422);
			expect(await response.json()).toEqual({
				error: 'Please review the limit override.',
				field_errors: { expires_at: 'Expiry must be later than the start time.' }
			});
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('rejects a past expiry against the default start time, once the window is actually evaluated', async () => {
			mockedOwnerSession.mockReturnValue(session());
			mockedResolveAccess.mockResolvedValue({} as never);
			mockedClient.mockReturnValue(clientWith({}) as never);

			const response = await PUT(
				putEvent(organizationId, limitKey, {
					override_state: 'on',
					limit_value: 25,
					expires_at: '2020-01-01T00:00:00.000Z'
				})
			);

			expect(response.status).toBe(422);
			expect(await response.json()).toEqual({ error: 'Expiry must be later than the start time.' });
		});

		it('clears the override and records an inherited event when set to inherit', async () => {
			mockedOwnerSession.mockReturnValue(session());
			mockedResolveAccess.mockResolvedValue({} as never);
			const client = clientWith({ before: { limit_key: limitKey, limit_value: 25 } });
			mockedClient.mockReturnValue(client as never);

			const response = await PUT(putEvent(organizationId, limitKey, { override_state: 'inherit' }));

			expect(response.status).toBe(200);
			expect(client.__delete).toHaveBeenCalled();
			expect(mockedRecordAudit).toHaveBeenCalledWith(
				expect.anything(),
				expect.objectContaining({ event_type: 'limit_override.inherited', target_key: limitKey })
			);
		});

		it('sets a numeric override and records an updated event', async () => {
			mockedOwnerSession.mockReturnValue(session());
			mockedResolveAccess.mockResolvedValue({} as never);
			const client = clientWith({});
			mockedClient.mockReturnValue(client as never);

			const response = await PUT(
				putEvent(organizationId, limitKey, {
					override_state: 'on',
					limit_value: 25,
					is_unlimited: false
				})
			);

			expect(response.status).toBe(200);
			expect(client.__upsert).toHaveBeenCalledWith(
				expect.objectContaining({
					organization_id: organizationId,
					limit_key: limitKey,
					limit_value: 25,
					is_unlimited: false
				}),
				{ onConflict: 'organization_id,limit_key' }
			);
			expect(mockedRecordAudit).toHaveBeenCalledWith(
				expect.anything(),
				expect.objectContaining({ event_type: 'limit_override.updated', target_key: limitKey })
			);
		});
	});

	describe('DELETE', () => {
		it('rejects callers without the separate owner session', async () => {
			mockedOwnerSession.mockReturnValue(null);

			const response = await DELETE(deleteEvent(organizationId, limitKey));

			expect(response.status).toBe(401);
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('validates the organization and limit identifiers', async () => {
			mockedOwnerSession.mockReturnValue(session());

			const response = await DELETE(deleteEvent('not-a-uuid', limitKey));

			expect(response.status).toBe(422);
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('returns 404 when the organization does not exist', async () => {
			mockedOwnerSession.mockReturnValue(session());
			mockedResolveAccess.mockRejectedValue(new OrganizationAccessNotFoundError());

			const response = await DELETE(deleteEvent(organizationId, limitKey));

			expect(response.status).toBe(404);
		});

		it('removes the override and records the audit trail', async () => {
			mockedOwnerSession.mockReturnValue(session());
			mockedResolveAccess.mockResolvedValue({} as never);
			const client = clientWith({ before: { limit_key: limitKey, limit_value: 25 } });
			mockedClient.mockReturnValue(client as never);

			const response = await DELETE(deleteEvent(organizationId, limitKey));

			expect(response.status).toBe(200);
			expect(client.__delete).toHaveBeenCalled();
			expect(mockedRecordAudit).toHaveBeenCalledWith(
				expect.anything(),
				expect.objectContaining({ event_type: 'limit_override.inherited', target_key: limitKey })
			);
		});
	});
});
