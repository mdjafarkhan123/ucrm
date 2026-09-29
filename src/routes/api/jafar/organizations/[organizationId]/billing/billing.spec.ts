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
const chargeId = '223e4567-e89b-12d3-a456-426614174000';
const receiptId = '323e4567-e89b-12d3-a456-426614174000';
const idempotencyKey = '423e4567-e89b-12d3-a456-426614174000';
const billing = { today: '2026-09-30', charges: [], receipts: [] };

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function event(body?: unknown, org = organizationId) {
	return {
		params: { organizationId: org },
		request: new Request(`http://localhost/api/jafar/organizations/${org}/billing`, {
			method: body === undefined ? 'GET' : 'POST',
			headers: { 'content-type': 'application/json' },
			body: body === undefined ? undefined : JSON.stringify(body)
		}),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

// The organization lookup answers `exists`; the ledger command answers `command`; the billing read
// answers the snapshot.
function billingClient(
	command: { data: unknown; error: { code: string; message: string } | null } = {
		data: { id: 'command-id' },
		error: null
	},
	exists = true
) {
	const rpc = vi.fn((name: string) =>
		Promise.resolve(
			name === 'owner_organization_billing' ? { data: billing, error: null } : command
		)
	);
	const builder = {
		select: () => builder,
		eq: () => builder,
		maybeSingle: () =>
			Promise.resolve({ data: exists ? { id: organizationId } : null, error: null })
	};
	return {
		from: (table: string) => {
			if (table === 'organizations') return builder;
			throw new Error(`Unexpected table: ${table}`);
		},
		rpc
	};
}

const recordPayment = {
	action: 'record_payment',
	idempotency_key: idempotencyKey,
	received_on: '2026-09-30',
	amount_usd_cents: 10000,
	method: 'Bank transfer',
	private_reference: 'TX-1',
	applications: [{ charge_id: chargeId, amount_usd_cents: 10000 }]
};

describe('platform owner billing ledger boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		expect((await GET(event())).status).toBe(401);
		expect((await POST(event(recordPayment))).status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('reads the billing snapshot', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = billingClient();
		mockedClient.mockReturnValue(client as never);

		const response = await GET(event());

		expect(response.status).toBe(200);
		expect((await response.json()).billing).toEqual(billing);
		expect(client.rpc).toHaveBeenCalledWith('owner_organization_billing', {
			target_organization_id: organizationId
		});
	});

	it('validates the command before database access', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await POST(event({ ...recordPayment, amount_usd_cents: -100 }));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.amount_usd_cents).toBeTruthy();
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('records a payment without a password and returns the refreshed billing', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = billingClient();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(recordPayment));

		expect(response.status).toBe(200);
		expect(mockedConsumeStepUp).not.toHaveBeenCalled();
		expect(client.rpc).toHaveBeenCalledWith(
			'record_organization_billing_receipt',
			expect.objectContaining({
				target_organization_id: organizationId,
				actor_owner_email: 'owner@example.com',
				idempotency_key: idempotencyKey,
				amount_usd_cents: 10000,
				applications: recordPayment.applications
			})
		);
		expect((await response.json()).billing).toEqual(billing);
	});

	it.each([
		{
			action: 'refund',
			idempotency_key: idempotencyKey,
			receipt_id: receiptId,
			refunded_on: '2026-09-30',
			amount_usd_cents: 500,
			method: 'Bank transfer',
			reason: 'Overpaid'
		},
		{
			action: 'void',
			idempotency_key: idempotencyKey,
			record_kind: 'charge',
			record_id: chargeId,
			reason: 'Added twice'
		},
		{
			action: 'correct_payment',
			idempotency_key: idempotencyKey,
			original_receipt_id: receiptId,
			received_on: '2026-09-30',
			amount_usd_cents: 500,
			method: 'Bank transfer',
			private_reference: 'TX-2',
			reason: 'Typo in amount'
		},
		{
			action: 'adjust_paid_through',
			idempotency_key: idempotencyKey,
			paid_through_date: '2026-10-31',
			reason: 'Agreed extension'
		}
	])('asks for the password again before $action', async (command) => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(event(command));

		expect(response.status).toBe(403);
		expect((await response.json()).step_up_required).toBe(true);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns not found for an unknown organization', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = billingClient(undefined, false);
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(recordPayment));

		expect(response.status).toBe(404);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('explains a charge that changed underneath the dialog', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue(
			billingClient({ data: null, error: { code: 'P0409', message: 'stale charge' } }) as never
		);

		const response = await POST(event(recordPayment));

		expect(response.status).toBe(409);
		expect((await response.json()).error).toContain('changed while you were looking');
	});

	it('turns a database rule message in cents into dollars', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue(
			billingClient({
				data: null,
				error: { code: '23514', message: 'Only 4900 cents is still owed on this charge.' }
			}) as never
		);

		const response = await POST(event(recordPayment));

		expect(response.status).toBe(409);
		expect((await response.json()).error).toBe('Only $49.00 is still owed on this charge.');
	});
});
