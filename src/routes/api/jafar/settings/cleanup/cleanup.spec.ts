import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({
	getOwnerSession: vi.fn(),
	consumeOwnerStepUp: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedConsumeStepUp = vi.mocked(consumeOwnerStepUp);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function getEvent() {
	return {} as Parameters<typeof GET>[0];
}

function postEvent(body: unknown = {}) {
	return {
		request: new Request('http://localhost/api/jafar/settings/cleanup', {
			method: 'POST',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function requestBody(overrides: Record<string, unknown> = {}) {
	return {
		organization_id: organizationId,
		typed_organization_name: 'Acme Roofing',
		...overrides
	};
}

describe('platform owner cleanup GET boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue(session());
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await GET(getEvent());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('lists open closure windows and unfinished deletion receipts', async () => {
		const closingRows = [
			{ id: 'closure-1', organization_id: organizationId, deadline_at: '2026-09-01' }
		];
		const unfinishedRows = [{ operation_id: 'op-1', status: 'failed_partial' }];
		const closureEq = vi.fn(() => ({
			order: vi.fn().mockResolvedValue({ data: closingRows, error: null })
		}));
		const receiptEq = vi.fn(() => ({
			order: vi.fn().mockResolvedValue({ data: unfinishedRows, error: null })
		}));
		mockedClient.mockReturnValue({
			from: (table: string) => {
				if (table === 'organization_closure_records') return { select: () => ({ eq: closureEq }) };
				if (table === 'organization_deletion_receipts')
					return { select: () => ({ eq: receiptEq }) };
				throw new Error(`unexpected table ${table}`);
			}
		} as never);

		const response = await GET(getEvent());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(closureEq).toHaveBeenCalledWith('status', 'pending_closure');
		expect(receiptEq).toHaveBeenCalledWith('status', 'failed_partial');
		expect(body).toEqual({
			closing_organizations: closingRows,
			unfinished_deletions: unfinishedRows
		});
	});
});

describe('platform owner cleanup POST boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(postEvent(requestBody()));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects a request missing a typed organization name', async () => {
		const response = await POST(postEvent(requestBody({ typed_organization_name: '' })));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires a recent password reconfirmation before deleting', async () => {
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(postEvent(requestBody()));

		expect(response.status).toBe(403);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the organization does not exist', async () => {
		mockedClient.mockReturnValue({
			from: () => ({
				select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: null, error: null }) }) })
			})
		} as never);

		const response = await POST(postEvent(requestBody()));

		expect(response.status).toBe(404);
	});

	it('rejects a typed organization name that does not match', async () => {
		mockedClient.mockReturnValue({
			from: () => ({
				select: () => ({
					eq: () => ({
						maybeSingle: async () => ({
							data: { id: organizationId, name: 'Acme Roofing' },
							error: null
						})
					})
				})
			})
		} as never);

		const response = await POST(postEvent(requestBody({ typed_organization_name: 'Wrong Name' })));

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.typed_organization_name).toBeDefined();
	});

	it('calls the purge RPC as an early manual trigger with the acting owner email', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: { applied: true, operation_id: 'op-1' }, error: null });
		mockedClient.mockReturnValue({
			rpc,
			from: () => ({
				select: () => ({
					eq: () => ({
						maybeSingle: async () => ({
							data: { id: organizationId, name: 'Acme Roofing' },
							error: null
						})
					})
				})
			})
		} as never);

		const response = await POST(postEvent(requestBody()));
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('apply_organization_purge', {
			target_organization_id: organizationId,
			purge_trigger_kind: 'early_manual',
			actor_owner_email: 'owner@example.com'
		});
		expect(body).toEqual({ operation_id: 'op-1', purged: true });
	});

	it('returns a conflict when the organization was already purged', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: { applied: false, reason: 'already_purged' }, error: null });
		mockedClient.mockReturnValue({
			rpc,
			from: () => ({
				select: () => ({
					eq: () => ({
						maybeSingle: async () => ({
							data: { id: organizationId, name: 'Acme Roofing' },
							error: null
						})
					})
				})
			})
		} as never);

		const response = await POST(postEvent(requestBody()));

		expect(response.status).toBe(409);
	});
});
