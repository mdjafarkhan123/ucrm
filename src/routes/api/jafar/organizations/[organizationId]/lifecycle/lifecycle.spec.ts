import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { resolveOrganizationAccess } from '$lib/server/access/effective';

vi.mock('$lib/server/auth/owner', () => ({
	getOwnerSession: vi.fn(),
	consumeOwnerStepUp: vi.fn()
}));
vi.mock('$lib/server/access/effective', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/effective')>(
		'$lib/server/access/effective'
	);
	return { ...actual, resolveOrganizationAccess: vi.fn() };
});
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedConsumeStepUp = vi.mocked(consumeOwnerStepUp);
const mockedResolveAccess = vi.mocked(resolveOrganizationAccess);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const idempotencyKey = '223e4567-e89b-12d3-a456-426614174000';

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

function event(id = organizationId, body: unknown = {}) {
	return {
		params: { organizationId: id },
		request: new Request(`http://localhost/api/jafar/organizations/${id}/lifecycle`, {
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
		suspension_category: 'nonpayment',
		reason: 'Invoice past due.',
		idempotency_key: idempotencyKey
	};
}

function reactivateBody() {
	return {
		status: 'active',
		reason: 'Paid-through date restored.',
		idempotency_key: idempotencyKey
	};
}

describe('platform owner lifecycle API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockReturnValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		mockedResolveAccess.mockResolvedValue({} as never);
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);

		const response = await PATCH(event(organizationId, suspendBody()));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the organization identifier before database access', async () => {
		const response = await PATCH(event('not-a-uuid', suspendBody()));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects a suspension without a category or reason', async () => {
		const response = await PATCH(
			event(organizationId, { status: 'suspended', idempotency_key: idempotencyKey })
		);

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires a recent password reconfirmation before suspending', async () => {
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await PATCH(event(organizationId, suspendBody()));

		expect(response.status).toBe(403);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires a recent password reconfirmation before reactivating', async () => {
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await PATCH(event(organizationId, reactivateBody()));

		expect(response.status).toBe(403);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('passes the category, reason, actor, and idempotency key to the atomic command on suspend', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { applied: true }, error: null });
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await PATCH(event(organizationId, suspendBody()));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('apply_organization_lifecycle_change', {
			target_organization_id: organizationId,
			target_status: 'suspended',
			target_suspension_category: 'nonpayment',
			idempotency_key: idempotencyKey,
			private_reason: 'Invoice past due.',
			actor_owner_email: 'owner@example.com'
		});
	});

	it('sends no suspension category to the atomic command on reactivate', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { applied: true }, error: null });
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await PATCH(event(organizationId, reactivateBody()));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('apply_organization_lifecycle_change', {
			target_organization_id: organizationId,
			target_status: 'active',
			target_suspension_category: null,
			idempotency_key: idempotencyKey,
			private_reason: 'Paid-through date restored.',
			actor_owner_email: 'owner@example.com'
		});
	});

	it('maps database validation and serialization conflicts to a safe conflict response', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: null, error: { code: '23514', message: 'private details' } });
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await PATCH(event(organizationId, reactivateBody()));

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({ error: 'private details' });
	});
});
