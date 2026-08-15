import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
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

function event(id = organizationId, body: unknown = {}) {
	return {
		params: { organizationId: id },
		request: new Request(`http://localhost/api/jafar/organizations/${id}/closure/restore`, {
			method: 'POST',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function requestBody(overrides: Record<string, unknown> = {}) {
	return {
		restoration_evidence_note: 'Called the administrator, verified identity, payment resolved.',
		idempotency_key: idempotencyKey,
		...overrides
	};
}

function organizationRow(overrides: Record<string, unknown> = {}) {
	return { id: organizationId, name: 'Acme Roofing', lifecycle_status: 'active', ...overrides };
}

function clientMock(rpcResult: { data: unknown; error: unknown }, organization: unknown = organizationRow()) {
	const rpc = vi.fn().mockResolvedValue(rpcResult);
	return {
		rpc,
		from: () => ({
			select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: organization, error: null }) }) })
		})
	} as never;
}

describe('platform owner closure-restore API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(event(organizationId, requestBody()));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the organization identifier before database access', async () => {
		const response = await POST(event('not-a-uuid', requestBody()));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects a request missing an evidence note', async () => {
		const response = await POST(
			event(organizationId, requestBody({ restoration_evidence_note: '' }))
		);

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires a recent password reconfirmation before restoring', async () => {
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(event(organizationId, requestBody()));

		expect(response.status).toBe(403);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('passes the evidence note, actor, and idempotency key to the atomic command', async () => {
		const client = clientMock({ data: { applied: true, lifecycle_status: 'active' }, error: null });
		mockedClient.mockReturnValue(client);

		const response = await POST(event(organizationId, requestBody()));

		expect(response.status).toBe(200);
		expect((client as { rpc: ReturnType<typeof vi.fn> }).rpc).toHaveBeenCalledWith(
			'apply_organization_closure_restore',
			{
				target_organization_id: organizationId,
				idempotency_key: idempotencyKey,
				restoration_evidence_note: 'Called the administrator, verified identity, payment resolved.',
				actor_owner_email: 'owner@example.com'
			}
		);
	});

	it('returns 404 when the organization cannot be found after restoring', async () => {
		mockedClient.mockReturnValue(
			clientMock({ data: { applied: true, lifecycle_status: 'active' }, error: null }, null)
		);

		const response = await POST(event(organizationId, requestBody()));

		expect(response.status).toBe(404);
	});

	it('maps database validation and serialization conflicts to a safe conflict response', async () => {
		mockedClient.mockReturnValue(
			clientMock({ data: null, error: { code: '23514', message: 'private details' } })
		);

		const response = await POST(event(organizationId, requestBody()));

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({ error: 'private details' });
	});
});
