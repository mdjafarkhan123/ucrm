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
	return {
		email: 'owner@example.com',
		sessionId: 'session-id',
		role: null,
		memberId: null,
		name: null
	};
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
		},
		{
			action: 'grant_free_access',
			idempotency_key: idempotencyKey,
			starts_on: '2026-09-30',
			ends_on: '2026-10-30',
			reason: 'Trial month'
		},
		{
			action: 'extend_free_access',
			idempotency_key: idempotencyKey,
			grant_id: chargeId,
			ends_on: '2026-11-30',
			reason: 'Longer trial'
		},
		{
			action: 'end_free_access',
			idempotency_key: idempotencyKey,
			grant_id: chargeId,
			reason: 'Trial over'
		}
	])('asks for the password again before $action', async (command) => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(false);

		const response = await POST(event(command));

		expect(response.status).toBe(403);
		expect((await response.json()).step_up_required).toBe(true);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('grants dated free access through the P5a command once the password is confirmed', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedConsumeStepUp.mockReturnValue(true);
		const client = billingClient();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(
			event({
				action: 'grant_free_access',
				idempotency_key: idempotencyKey,
				starts_on: '2026-09-30',
				ends_on: '2026-10-30',
				reason: 'Trial month'
			})
		);

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith('grant_organization_free_access', {
			target_organization_id: organizationId,
			actor_owner_email: 'owner@example.com',
			idempotency_key: idempotencyKey,
			starts_on: '2026-09-30',
			ends_on: '2026-10-30',
			reason: 'Trial month'
		});
	});

	it('refuses free access with no end date', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await POST(
			event({
				action: 'grant_free_access',
				idempotency_key: idempotencyKey,
				starts_on: '2026-09-30',
				reason: 'Forever'
			})
		);

		expect(response.status).toBe(422);
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

	describe('package changes (P8b)', () => {
		const editionId = '523e4567-e89b-12d3-a456-426614174000';
		const changePackage = {
			action: 'change_package',
			idempotency_key: idempotencyKey,
			edition_id: editionId,
			billing_interval: 'year',
			timing: 'now',
			expected_effective_date: '2026-09-30',
			expected_credit_usd_cents: 12000,
			expected_charge_usd_cents: 149000,
			reason: 'Customer asked for yearly billing'
		};

		it('changes the package without a password, passing the reviewed figures through', async () => {
			mockedOwnerSession.mockResolvedValue(session());
			const client = billingClient();
			mockedClient.mockReturnValue(client as never);

			const response = await POST(event(changePackage));

			expect(response.status).toBe(200);
			expect(mockedConsumeStepUp).not.toHaveBeenCalled();
			expect(client.rpc).toHaveBeenCalledWith('change_organization_package', {
				target_organization_id: organizationId,
				actor_owner_email: 'owner@example.com',
				idempotency_key: idempotencyKey,
				target_edition_id: editionId,
				billing_interval: 'year',
				timing: 'now',
				expected_effective_date: '2026-09-30',
				expected_credit_usd_cents: 12000,
				expected_charge_usd_cents: 149000,
				reason: 'Customer asked for yearly billing',
				target_offer_id: undefined,
				offer_code: undefined,
				keep_offer: false
			});
		});

		it('tells the dialog to reload the preview when the figures moved', async () => {
			mockedOwnerSession.mockResolvedValue(session());
			mockedClient.mockReturnValue(
				billingClient({ data: null, error: { code: 'P0409', message: 'moved on' } }) as never
			);

			const response = await POST(event(changePackage));
			const body = await response.json();

			expect(response.status).toBe(409);
			expect(body.preview_stale).toBe(true);
		});

		it('refuses a change without a reason or a known start', async () => {
			mockedOwnerSession.mockResolvedValue(session());

			const response = await POST(event({ ...changePackage, reason: '', timing: 'someday' }));
			const body = await response.json();

			expect(response.status).toBe(422);
			expect(body.field_errors.reason).toBeTruthy();
			expect(body.field_errors.timing).toBeTruthy();
			expect(mockedClient).not.toHaveBeenCalled();
		});

		it('cancels a scheduled change', async () => {
			mockedOwnerSession.mockResolvedValue(session());
			const client = billingClient();
			mockedClient.mockReturnValue(client as never);

			const response = await POST(
				event({
					action: 'cancel_package_change',
					idempotency_key: idempotencyKey,
					agreement_id: editionId,
					reason: 'Customer changed their mind'
				})
			);

			expect(response.status).toBe(200);
			expect(client.rpc).toHaveBeenCalledWith('cancel_scheduled_package_change', {
				target_organization_id: organizationId,
				actor_owner_email: 'owner@example.com',
				idempotency_key: idempotencyKey,
				agreement_id: editionId,
				reason: 'Customer changed their mind'
			});
		});

		it('uses change credit on a charge', async () => {
			mockedOwnerSession.mockResolvedValue(session());
			const client = billingClient();
			mockedClient.mockReturnValue(client as never);

			const response = await POST(
				event({
					action: 'apply_change_credit',
					idempotency_key: idempotencyKey,
					credit_note_id: receiptId,
					charge_id: chargeId,
					amount_usd_cents: 2500
				})
			);

			expect(response.status).toBe(200);
			expect(client.rpc).toHaveBeenCalledWith('apply_organization_billing_credit_note', {
				target_organization_id: organizationId,
				actor_owner_email: 'owner@example.com',
				idempotency_key: idempotencyKey,
				credit_note_id: receiptId,
				charge_id: chargeId,
				amount_usd_cents: 2500
			});
		});
	});
});
