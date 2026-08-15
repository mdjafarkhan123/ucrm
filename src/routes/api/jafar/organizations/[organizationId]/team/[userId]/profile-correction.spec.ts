import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { recordOperationOutcome } from '$lib/server/events/outbox';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/events/outbox', () => ({ recordOperationOutcome: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedRecordOutcome = vi.mocked(recordOperationOutcome);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const userId = '223e4567-e89b-12d3-a456-426614174000';
const idempotencyKey = '323e4567-e89b-12d3-a456-426614174000';

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function patchEvent(body: unknown, orgId = organizationId, memberId = userId) {
	return {
		params: { organizationId: orgId, userId: memberId },
		request: new Request(
			`http://localhost/api/jafar/organizations/${orgId}/team/${memberId}`,
			{ method: 'PATCH', body: JSON.stringify(body), headers: { 'content-type': 'application/json' } }
		)
	} as Parameters<typeof PATCH>[0];
}

function mockClient(options: {
	role?: string;
	fullName?: string | null;
	email?: string | null;
	getUserByIdFails?: boolean;
	updateUserById?: () => Promise<{ error: unknown }>;
	rpc?: (name: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
}) {
	return {
		from: (table: string) => {
			if (table === 'organization_members') {
				return {
					select: () => ({
						eq: () => ({
							eq: () => ({
								maybeSingle: async () => ({
									data: { user_id: userId, role: options.role ?? 'field' },
									error: null
								})
							})
						})
					})
				};
			}
			if (table === 'profiles') {
				return {
					select: () => ({
						eq: () => ({
							maybeSingle: async () => ({
								data: { full_name: options.fullName ?? 'Fin Tech' },
								error: null
							})
						})
					})
				};
			}
			throw new Error(`unexpected table ${table}`);
		},
		auth: {
			admin: {
				getUserById: async () =>
					options.getUserByIdFails
						? { data: { user: null }, error: new Error('Auth admin API unavailable.') }
						: { data: { user: { email: options.email ?? 'fin@example.com' } }, error: null },
				updateUserById: options.updateUserById ?? (async () => ({ error: null }))
			}
		},
		rpc: options.rpc ?? (async () => ({ data: { event_id: 'evt-1' }, error: null }))
	} as never;
}

function validBody(overrides: Record<string, unknown> = {}) {
	return {
		full_name: 'Finley Tech',
		reason: 'Contractor asked us to fix a typo in the name.',
		idempotency_key: idempotencyKey,
		...overrides
	};
}

describe('team member profile correction PATCH boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue(session());
	});

	it('rejects callers without the owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await PATCH(patchEvent(validBody()));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates identifiers before reading the database', async () => {
		const response = await PATCH(patchEvent(validBody(), 'not-a-uuid'));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects a body with neither name nor email', async () => {
		mockedClient.mockReturnValue(mockClient({}));

		const response = await PATCH(patchEvent({ reason: 'x'.repeat(5), idempotency_key: idempotencyKey }));

		expect(response.status).toBe(422);
	});

	it('404s when the member is not in this organization', async () => {
		mockedClient.mockReturnValue({
			from: (table: string) => {
				if (table === 'organization_members') {
					return {
						select: () => ({
							eq: () => ({ eq: () => ({ maybeSingle: async () => ({ data: null, error: null }) }) })
						})
					};
				}
				return {
					select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: null, error: null }) }) })
				};
			},
			auth: { admin: { getUserById: async () => ({ data: { user: null }, error: null }) } }
		} as never);

		const response = await PATCH(patchEvent(validBody()));

		expect(response.status).toBe(404);
	});

	it('blocks an email change for an owner or admin, pointing to administrator recovery', async () => {
		mockedClient.mockReturnValue(mockClient({ role: 'admin', email: 'admin@example.com' }));

		const response = await PATCH(patchEvent(validBody({ email: 'new@example.com' })));

		expect(response.status).toBe(409);
	});

	it('allows a name and email correction for a non-admin member and revokes sessions on email change', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { event_id: 'evt-1' }, error: null });
		mockedClient.mockReturnValue(
			mockClient({ role: 'field', fullName: 'Old Name', email: 'old@example.com', rpc })
		);

		const response = await PATCH(
			patchEvent(validBody({ full_name: 'New Name', email: 'new@example.com' }))
		);
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('apply_organization_member_profile_correction', {
			target_organization_id: organizationId,
			target_user_id: userId,
			new_full_name: 'New Name',
			email_changed: true,
			old_email: 'old@example.com',
			new_email: 'new@example.com',
			private_reason: expect.any(String),
			actor_owner_email: 'owner@example.com'
		});
		expect(body.member.email).toBe('new@example.com');
	});

	it('still saves a name-only correction when the auth email lookup fails (Riverside Legacy Demo regression)', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { event_id: 'evt-1' }, error: null });
		mockedClient.mockReturnValue(
			mockClient({ role: 'owner', fullName: 'Old Name', getUserByIdFails: true, rpc })
		);

		const response = await PATCH(patchEvent(validBody({ full_name: 'New Name' })));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith(
			'apply_organization_member_profile_correction',
			expect.objectContaining({ new_full_name: 'New Name', email_changed: false })
		);
	});

	it('502s an email correction when the auth email lookup fails instead of guessing', async () => {
		mockedClient.mockReturnValue(mockClient({ role: 'field', getUserByIdFails: true }));

		const response = await PATCH(
			patchEvent(validBody({ email: 'new@example.com', full_name: null }))
		);

		expect(response.status).toBe(502);
	});

	it('queues a retryable operation and returns 502 when the auth update fails', async () => {
		mockedClient.mockReturnValue(
			mockClient({
				role: 'field',
				email: 'old@example.com',
				updateUserById: async () => ({ error: new Error('GoTrue unavailable') })
			})
		);

		const response = await PATCH(
			patchEvent(validBody({ email: 'new@example.com', full_name: null }))
		);

		expect(response.status).toBe(502);
		expect(mockedRecordOutcome).toHaveBeenCalledWith(
			expect.anything(),
			expect.objectContaining({
				operationType: 'organization_member_profile_correction',
				success: false
			})
		);
	});

	it('rejects a correction where nothing actually changes', async () => {
		mockedClient.mockReturnValue(mockClient({ fullName: 'Finley Tech' }));

		const response = await PATCH(patchEvent(validBody({ full_name: 'Finley Tech' })));

		expect(response.status).toBe(422);
	});
});
