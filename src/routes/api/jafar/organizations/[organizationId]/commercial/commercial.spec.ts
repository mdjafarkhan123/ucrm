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
const originalEventId = '223e4567-e89b-12d3-a456-426614174000';
const idempotencyKey = '323e4567-e89b-42d3-a456-426614174000';

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function getEvent(id = organizationId) {
	return { params: { organizationId: id } } as Parameters<typeof GET>[0];
}

function postEvent(body: unknown, id = organizationId) {
	return {
		params: { organizationId: id },
		request: new Request(`http://localhost/api/jafar/organizations/${id}/commercial`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function query(data: unknown) {
	const result = { data, error: null };
	const builder = {
		select: () => builder,
		eq: () => builder,
		in: () => builder,
		order: () => builder,
		maybeSingle: () => Promise.resolve(result),
		then: (resolve: (value: typeof result) => unknown) => Promise.resolve(result).then(resolve)
	};
	return builder;
}

function commercialClient(
	lifecycleStatus: 'active' | 'suspended' = 'active',
	rpcResult: { data: unknown; error: { code: string; message: string } | null } = {
		data: { applied: true, event_id: 'event-1' },
		error: null
	}
) {
	return {
		from: (table: string) => {
			if (table === 'organizations')
				return query({
					id: organizationId,
					name: 'Ridgeway Electric',
					lifecycle_status: lifecycleStatus
				});
			if (table === 'organization_commercial_state')
				return query({
					paid_through_date: '2026-08-31',
					paid_through_source: 'renewal',
					grace_ends_at: '2026-09-08T03:59:59.999Z',
					grace_basis_timezone: 'America/New_York',
					last_event_id: originalEventId,
					state_version: 2,
					updated_at: '2026-08-13T00:00:00Z'
				});
			if (table === 'organization_commercial_settings')
				return query({ commercial_timezone: 'America/New_York', timezone_source: 'imported' });
			if (table === 'organization_commercial_events')
				return query([
					{
						id: originalEventId,
						event_kind: 'initial_payment_confirmed',
						occurred_at: '2026-08-01T00:00:00Z',
						summary: 'Initial payment confirmed.',
						amount_usd_cents: 9900,
						paid_through_after: '2026-08-31',
						private_reference: 'bank-1'
					}
				]);
			if (table === 'organization_closure_records') return query(null);
			throw new Error(`Unexpected table: ${table}`);
		},
		rpc: vi.fn().mockResolvedValue(rpcResult)
	};
}

describe('platform owner commercial API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await GET(getEvent());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates each commercial action before database access', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await POST(
			postEvent({
				action: 'refund',
				idempotency_key: idempotencyKey,
				original_event_id: originalEventId,
				amount_usd_cents: -500,
				paid_through_effect: 'unchanged',
				private_reference: 'bank-2',
				private_reason: 'Customer refund'
			})
		);

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires password reconfirmation only when renewal also reactivates', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(
			postEvent({
				action: 'renewal',
				idempotency_key: idempotencyKey,
				amount_usd_cents: 9900,
				paid_through_effect: 'set',
				paid_through_date: '2026-09-30',
				private_reference: 'bank-2',
				reactivate: true
			})
		);

		expect(response.status).toBe(403);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('records a plain renewal without changing lifecycle or requiring step-up', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = commercialClient('active');
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			postEvent({
				action: 'renewal',
				idempotency_key: idempotencyKey,
				amount_usd_cents: 9900,
				paid_through_effect: 'set',
				paid_through_date: '2026-09-30',
				private_reference: 'bank-2',
				reactivate: false
			})
		);

		expect(response.status).toBe(200);
		expect(mockedConsumeStepUp).not.toHaveBeenCalled();
		expect(client.rpc).toHaveBeenCalledWith(
			'apply_organization_late_renewal_reactivation',
			expect.objectContaining({
				target_organization_id: organizationId,
				idempotency_key: idempotencyKey,
				reactivate: false,
				paid_through_date: '2026-09-30'
			})
		);
	});

	it('returns a conflict when an adjustment references an invalid original event', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue(
			commercialClient('active', {
				data: null,
				error: { code: '23514', message: 'The original event is not valid.' }
			}) as never
		);

		const response = await POST(
			postEvent({
				action: 'reversal',
				idempotency_key: idempotencyKey,
				original_event_id: originalEventId,
				amount_usd_cents: 9900,
				paid_through_effect: 'unchanged',
				private_reference: 'bank-3',
				private_reason: 'Bank reversed the payment'
			})
		);

		expect(response.status).toBe(409);
		expect((await response.json()).error).toBe('The original event is not valid.');
	});

	it('includes the open closure record when the organization is pending closure', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = commercialClient('active');
		const closingRecord = {
			id: 'closure-1',
			reason: 'Contractor requested closure',
			started_at: '2026-08-01T00:00:00Z',
			deadline_at: '2026-08-31T00:00:00Z'
		};
		const baseFrom = client.from;
		client.from = ((table: string) =>
			table === 'organization_closure_records' ? query(closingRecord) : baseFrom(table)) as never;
		mockedClient.mockReturnValue(client as never);

		const response = await GET(getEvent());
		const result = await response.json();

		expect(response.status).toBe(200);
		expect(result.closure).toEqual(closingRecord);
	});
});
