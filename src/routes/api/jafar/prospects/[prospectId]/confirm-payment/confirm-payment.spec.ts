import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const prospectId = '123e4567-e89b-12d3-a456-426614174000';

const validBody = {
	received_on: '2026-09-29',
	amount_usd_cents: 129000,
	method: 'Bank transfer',
	private_reference: 'e-transfer #4821',
	note: 'Paid the yearly price upfront'
};

function event(id: string, body: unknown = validBody) {
	return {
		params: { prospectId: id },
		request: new Request('http://localhost/api/jafar/prospects/' + id + '/confirm-payment', {
			method: 'POST',
			body: JSON.stringify(body)
		}),
		url: new URL('http://localhost/api/jafar/prospects/' + id + '/confirm-payment'),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function clientWith(rpcError: { message: string } | null = null) {
	const rpc = vi.fn().mockResolvedValue({ data: 'confirmation-id', error: rpcError });
	return { rpc };
}

describe('platform owner prospect payment confirmation API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		} as never);
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const response = await POST(event(prospectId));
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates every receipt field before database access', async () => {
		const response = await POST(
			event(prospectId, {
				received_on: '2026-02-30',
				amount_usd_cents: 0,
				method: '',
				private_reference: ''
			})
		);
		expect(response.status).toBe(422);
		const body = (await response.json()) as { field_errors: Record<string, string> };
		expect(Object.keys(body.field_errors)).toEqual(
			expect.arrayContaining(['received_on', 'amount_usd_cents', 'method', 'private_reference'])
		);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('records the receipt with its date, method, reference, and note', async () => {
		const client = clientWith();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith('confirm_onboarding_application_payment', {
			target_application_id: prospectId,
			actor_email: 'owner@example.com',
			received_on: '2026-09-29',
			amount_usd_cents: 129000,
			method: 'Bank transfer',
			private_reference: 'e-transfer #4821',
			note: 'Paid the yearly price upfront'
		});
	});

	it('explains a partial payment in dollars on the amount field', async () => {
		mockedClient.mockReturnValue(
			clientWith({
				message:
					'The payment is less than the agreed first payment of 129000 cents. Record it once the full amount has arrived.'
			}) as never
		);

		const response = await POST(event(prospectId, { ...validBody, amount_usd_cents: 100000 }));
		expect(response.status).toBe(422);
		const body = (await response.json()) as { field_errors: Record<string, string> };
		expect(body.field_errors.amount_usd_cents).toContain('$1,290.00');
	});

	it('answers 409 when the application already moved past payment', async () => {
		mockedClient.mockReturnValue(
			clientWith({ message: 'This application can no longer be confirmed for payment.' }) as never
		);
		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
	});

	it('answers 404 for an unknown application', async () => {
		mockedClient.mockReturnValue(
			clientWith({ message: 'The onboarding application does not exist.' }) as never
		);
		const response = await POST(event(prospectId));
		expect(response.status).toBe(404);
	});
});
