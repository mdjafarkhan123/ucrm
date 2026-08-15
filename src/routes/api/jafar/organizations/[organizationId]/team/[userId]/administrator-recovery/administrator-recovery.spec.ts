import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { recordOperationOutcome } from '$lib/server/events/outbox';
import { sendAdministratorEmailRecoveryNotices } from '$lib/server/jafar/team-notifications';

vi.mock('$lib/server/auth/owner', () => ({
	getOwnerSession: vi.fn(),
	consumeOwnerStepUp: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/events/outbox', () => ({ recordOperationOutcome: vi.fn() }));
vi.mock('$lib/server/jafar/team-notifications', () => ({
	sendAdministratorEmailRecoveryNotices: vi.fn()
}));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedConsumeStepUp = vi.mocked(consumeOwnerStepUp);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedRecordOutcome = vi.mocked(recordOperationOutcome);
const mockedSendNotices = vi.mocked(sendAdministratorEmailRecoveryNotices);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const userId = '223e4567-e89b-12d3-a456-426614174000';
const idempotencyKey = '323e4567-e89b-12d3-a456-426614174000';

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function postEvent(body: unknown, orgId = organizationId, memberId = userId) {
	return {
		params: { organizationId: orgId, userId: memberId },
		request: new Request(
			`http://localhost/api/jafar/organizations/${orgId}/team/${memberId}/administrator-recovery`,
			{ method: 'POST', body: JSON.stringify(body), headers: { 'content-type': 'application/json' } }
		)
	} as Parameters<typeof POST>[0];
}

function validBody(overrides: Record<string, unknown> = {}) {
	return {
		new_email: 'new-admin@example.com',
		evidence_summary: 'Called the number on file, confirmed business name and last login date.',
		reason: 'Administrator lost access to their old inbox.',
		idempotency_key: idempotencyKey,
		...overrides
	};
}

function mockClient(options: {
	role?: string;
	currentEmail?: string | null;
	getUserByIdFails?: boolean;
	emailAvailable?: boolean;
	updateUserById?: () => Promise<{ error: unknown }>;
	rpc?: (name: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
	organizationFound?: boolean;
	membershipFound?: boolean;
}) {
	return {
		from: (table: string) => {
			if (table === 'organizations') {
				return {
					select: () => ({
						eq: () => ({
							maybeSingle: async () => ({
								data:
									options.organizationFound === false
										? null
										: { id: organizationId, name: 'Ridgeway Electric' },
								error: null
							})
						})
					})
				};
			}
			if (table === 'organization_members') {
				return {
					select: () => ({
						eq: () => ({
							eq: () => ({
								maybeSingle: async () => ({
									data:
										options.membershipFound === false
											? null
											: { user_id: userId, role: options.role ?? 'admin' },
									error: null
								})
							})
						})
					})
				};
			}
			throw new Error(`unexpected table ${table}`);
		},
		auth: {
			admin: {
				getUserById: options.getUserByIdFails
					? async () => {
							throw new Error('Database error loading user');
						}
					: async () => ({
							data: { user: { email: options.currentEmail ?? 'old-admin@example.com' } },
							error: null
						}),
				updateUserById: options.updateUserById ?? (async () => ({ error: null }))
			}
		},
		rpc: async (name: string, args: Record<string, unknown>) => {
			if (name === 'owner_email_is_available') {
				return { data: options.emailAvailable ?? true, error: null };
			}
			if (options.rpc) return options.rpc(name, args);
			return { data: { event_id: 'evt-1' }, error: null };
		}
	} as never;
}

describe('administrator email recovery POST boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
	});

	it('rejects callers without the owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates identifiers before reading the database', async () => {
		const response = await POST(postEvent(validBody(), 'not-a-uuid'));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the body before checking step-up', async () => {
		const response = await POST(postEvent({ new_email: 'not-an-email' }));

		expect(response.status).toBe(422);
		expect(mockedConsumeStepUp).not.toHaveBeenCalled();
	});

	it('requires a recent password reconfirmation', async () => {
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(403);
		const body = await response.json();
		expect(body.step_up_required).toBe(true);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('404s when the organization does not exist', async () => {
		mockedClient.mockReturnValue(mockClient({ organizationFound: false }));

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(404);
	});

	it('blocks recovery for a non-admin, non-owner member', async () => {
		mockedClient.mockReturnValue(mockClient({ role: 'field' }));

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(409);
	});

	it('blocks recovery when the new email is already used elsewhere on the platform', async () => {
		mockedClient.mockReturnValue(mockClient({ emailAvailable: false }));

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(409);
	});

	it('recovers an administrator, revokes sessions via the RPC, and emails both addresses', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { event_id: 'evt-1' }, error: null });
		mockedClient.mockReturnValue(
			mockClient({ role: 'owner', currentEmail: 'old-admin@example.com', rpc })
		);

		const response = await POST(postEvent(validBody()));
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('apply_organization_administrator_email_recovery', {
			target_organization_id: organizationId,
			target_user_id: userId,
			old_email: 'old-admin@example.com',
			new_email: 'new-admin@example.com',
			evidence_summary: expect.any(String),
			private_reason: expect.any(String),
			actor_owner_email: 'owner@example.com'
		});
		expect(mockedSendNotices).toHaveBeenCalledWith(
			expect.anything(),
			expect.objectContaining({
				oldEmail: 'old-admin@example.com',
				newEmail: 'new-admin@example.com',
				businessName: 'Ridgeway Electric'
			})
		);
		expect(body.member.email).toBe('new-admin@example.com');
	});

	it('still recovers when the auth email lookup fails, skipping only the old-address notice', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { event_id: 'evt-1' }, error: null });
		mockedClient.mockReturnValue(mockClient({ role: 'owner', getUserByIdFails: true, rpc }));

		const response = await POST(postEvent(validBody()));
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('apply_organization_administrator_email_recovery', {
			target_organization_id: organizationId,
			target_user_id: userId,
			old_email: null,
			new_email: 'new-admin@example.com',
			evidence_summary: expect.any(String),
			private_reason: expect.any(String),
			actor_owner_email: 'owner@example.com'
		});
		expect(mockedSendNotices).toHaveBeenCalledWith(
			expect.anything(),
			expect.objectContaining({ oldEmail: null, newEmail: 'new-admin@example.com' })
		);
		expect(body.member.email).toBe('new-admin@example.com');
	});

	it('queues a retryable operation and returns 502 when the auth update fails', async () => {
		mockedClient.mockReturnValue(
			mockClient({
				role: 'owner',
				updateUserById: async () => ({ error: new Error('GoTrue unavailable') })
			})
		);

		const response = await POST(postEvent(validBody()));

		expect(response.status).toBe(502);
		expect(mockedRecordOutcome).toHaveBeenCalledWith(
			expect.anything(),
			expect.objectContaining({
				operationType: 'organization_administrator_email_recovery',
				success: false
			})
		);
		expect(mockedSendNotices).not.toHaveBeenCalled();
	});
});
