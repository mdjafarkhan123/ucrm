import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
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
const grantId = '223e4567-e89b-12d3-a456-426614174000';
const idempotencyKey = '323e4567-e89b-42d3-a456-426614174000';

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

function getEvent(id = organizationId) {
	return { params: { organizationId: id } } as Parameters<typeof GET>[0];
}

function postEvent(body: unknown, id = organizationId) {
	return {
		params: { organizationId: id },
		request: new Request(`http://localhost/api/jafar/organizations/${id}/free-access`, {
			method: 'POST',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function query(data: unknown) {
	const result = { data, error: null };
	const builder = {
		select: () => builder,
		eq: () => builder,
		order: () => builder,
		limit: () => builder,
		maybeSingle: () =>
			Promise.resolve({ ...result, data: Array.isArray(data) ? (data[0] ?? null) : data }),
		then: (resolve: (value: typeof result) => unknown) => Promise.resolve(result).then(resolve)
	};
	return builder;
}

function freeAccessClient(
	rpcResult: { data: unknown; error: { code: string; message: string } | null } = {
		data: { applied: true },
		error: null
	}
) {
	return {
		from: (table: string) => {
			if (table === 'organizations')
				return query({ id: organizationId, name: 'Ridgeway Electric' });
			if (table === 'organization_package_assignments')
				return query({ id: 'assignment-1', package_version_id: 'version-1' });
			if (table === 'organization_free_access_events') return query([]);
			throw new Error(`Unexpected table: ${table}`);
		},
		rpc: vi.fn().mockResolvedValue(rpcResult)
	};
}

describe('platform owner free-access API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockReturnValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		mockedResolveAccess.mockResolvedValue({ free_access: { active: null, future: null } } as never);
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);

		const response = await GET(getEvent());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates a grant command before database access', async () => {
		const response = await POST(
			postEvent({ action: 'grant', reason: 'Missing a start date' })
		);

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires a recent password reconfirmation before granting forever access', async () => {
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(
			postEvent({
				action: 'grant',
				starts_at: '2026-08-14',
				reason: 'Goodwill gesture',
				idempotency_key: idempotencyKey
			})
		);

		expect(response.status).toBe(403);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires a recent password reconfirmation before converting to forever access', async () => {
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(
			postEvent({
				action: 'convert_to_forever',
				grant_id: grantId,
				reason: 'Escalation',
				idempotency_key: idempotencyKey
			})
		);

		expect(response.status).toBe(403);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('does not require reconfirmation for a time-bound grant', async () => {
		const client = freeAccessClient();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			postEvent({
				action: 'grant',
				starts_at: '2026-08-14',
				access_until_date: '2026-12-31',
				reason: 'Trial extension',
				idempotency_key: idempotencyKey
			})
		);

		expect(mockedConsumeStepUp).not.toHaveBeenCalled();
		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith('apply_organization_free_access_change', {
			target_organization_id: organizationId,
			target_action: 'grant',
			target_grant_id: null,
			target_starts_at: '2026-08-14',
			target_access_until_date: '2026-12-31',
			idempotency_key: idempotencyKey,
			private_reason: 'Trial extension',
			actor_owner_email: 'owner@example.com'
		});
	});

	it('does not require reconfirmation for ending free access', async () => {
		const client = freeAccessClient();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			postEvent({
				action: 'end',
				grant_id: grantId,
				reason: 'Trial ended',
				idempotency_key: idempotencyKey
			})
		);

		expect(mockedConsumeStepUp).not.toHaveBeenCalled();
		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith('apply_organization_free_access_change', {
			target_organization_id: organizationId,
			target_action: 'end',
			target_grant_id: grantId,
			target_starts_at: null,
			target_access_until_date: null,
			idempotency_key: idempotencyKey,
			private_reason: 'Trial ended',
			actor_owner_email: 'owner@example.com'
		});
	});

	it('maps database validation and serialization conflicts to a safe conflict response', async () => {
		mockedClient.mockReturnValue(
			freeAccessClient({
				data: null,
				error: { code: '23514', message: 'An active free access grant already exists.' }
			}) as never
		);

		const response = await POST(
			postEvent({
				action: 'grant',
				starts_at: '2026-08-14',
				reason: 'Duplicate grant',
				idempotency_key: idempotencyKey
			})
		);

		expect(response.status).toBe(409);
		expect((await response.json()).error).toBe('An active free access grant already exists.');
	});
});
