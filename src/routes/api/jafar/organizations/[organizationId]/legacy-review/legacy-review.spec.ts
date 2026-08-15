import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, PATCH } from './+server';
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
const idempotencyKey = '223e4567-e89b-12d3-a456-426614174000';

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function getEvent(id = organizationId) {
	return { params: { organizationId: id } } as Parameters<typeof GET>[0];
}

function patchEvent(id = organizationId, body: unknown = {}) {
	return {
		params: { organizationId: id },
		request: new Request(`http://localhost/api/jafar/organizations/${id}/legacy-review`, {
			method: 'PATCH',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		cookies: {}
	} as Parameters<typeof PATCH>[0];
}

function suspendBody() {
	return {
		status: 'suspended',
		suspension_category: 'other',
		reason: 'Legacy row, no administrator on record.',
		idempotency_key: idempotencyKey
	};
}

function activateBody() {
	return {
		status: 'active',
		reason: 'Reviewed: paid, administrator ready.',
		idempotency_key: idempotencyKey
	};
}

function organizationRow() {
	return { id: organizationId, name: 'Legacy Co', lifecycle_status: 'pending_setup' };
}

describe('platform owner legacy-review GET boundary', () => {
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

	it('validates the organization identifier before database access', async () => {
		const response = await GET(getEvent('not-a-uuid'));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the organization does not exist', async () => {
		mockedClient.mockReturnValue({
			from: () => ({
				select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: null, error: null }) }) })
			})
		} as never);

		const response = await GET(getEvent());

		expect(response.status).toBe(404);
	});

	it('returns the organization and readiness checklist from the database', async () => {
		const readiness = {
			package_assigned: false,
			administrator_exists: false,
			administrator_login_ready: false,
			paid_through_eligible: false,
			free_access_active: false
		};
		const rpc = vi.fn().mockResolvedValue({ data: readiness, error: null });
		mockedClient.mockReturnValue({
			from: () => ({
				select: () => ({
					eq: () => ({ maybeSingle: async () => ({ data: organizationRow(), error: null }) })
				})
			}),
			rpc
		} as never);

		const response = await GET(getEvent());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('organization_legacy_readiness', {
			target_organization_id: organizationId
		});
		expect(body).toEqual({ organization: organizationRow(), readiness });
	});
});

describe('platform owner legacy-review PATCH boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await PATCH(patchEvent(organizationId, suspendBody()));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the organization identifier before database access', async () => {
		const response = await PATCH(patchEvent('not-a-uuid', suspendBody()));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects a suspension without a category or reason', async () => {
		const response = await PATCH(
			patchEvent(organizationId, { status: 'suspended', idempotency_key: idempotencyKey })
		);

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('does not require step-up before suspending', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { applied: true }, error: null });
		mockedClient.mockReturnValue({
			rpc,
			from: () => ({
				select: () => ({
					eq: () => ({ maybeSingle: async () => ({ data: organizationRow(), error: null }) })
				})
			})
		} as never);

		const response = await PATCH(patchEvent(organizationId, suspendBody()));

		expect(response.status).toBe(200);
		expect(mockedConsumeStepUp).not.toHaveBeenCalled();
	});

	it('requires a recent password reconfirmation before activating', async () => {
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await PATCH(patchEvent(organizationId, activateBody()));

		expect(response.status).toBe(403);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('passes the category, reason, actor, and idempotency key to the atomic command on suspend', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { applied: true }, error: null });
		mockedClient.mockReturnValue({
			rpc,
			from: () => ({
				select: () => ({
					eq: () => ({ maybeSingle: async () => ({ data: organizationRow(), error: null }) })
				})
			})
		} as never);

		const response = await PATCH(patchEvent(organizationId, suspendBody()));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('apply_organization_pending_setup_reconciliation', {
			target_organization_id: organizationId,
			target_status: 'suspended',
			target_suspension_category: 'other',
			idempotency_key: idempotencyKey,
			private_reason: 'Legacy row, no administrator on record.',
			actor_owner_email: 'owner@example.com'
		});
	});

	it('sends no suspension category to the atomic command on activate', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { applied: true }, error: null });
		mockedClient.mockReturnValue({
			rpc,
			from: () => ({
				select: () => ({
					eq: () => ({ maybeSingle: async () => ({ data: organizationRow(), error: null }) })
				})
			})
		} as never);

		const response = await PATCH(patchEvent(organizationId, activateBody()));

		expect(response.status).toBe(200);
		expect(mockedConsumeStepUp).toHaveBeenCalled();
		expect(rpc).toHaveBeenCalledWith('apply_organization_pending_setup_reconciliation', {
			target_organization_id: organizationId,
			target_status: 'active',
			target_suspension_category: null,
			idempotency_key: idempotencyKey,
			private_reason: 'Reviewed: paid, administrator ready.',
			actor_owner_email: 'owner@example.com'
		});
	});

	it('maps database validation and readiness failures to a safe conflict response', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'Assign a published package version before activating.' }
		});
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await PATCH(patchEvent(organizationId, activateBody()));

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({
			error: 'Assign a published package version before activating.'
		});
	});
});
