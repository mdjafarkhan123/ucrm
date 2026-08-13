import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/jafar/owner-alerts', () => ({ raiseOwnerAlert: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedRaiseAlert = vi.mocked(raiseOwnerAlert);

const prospectId = '123e4567-e89b-12d3-a456-426614174000';

const validBody = { reason: 'Bank confirmed the transfer was reversed by the sender.' };

function event(id: string, body: unknown = validBody) {
	return {
		params: { prospectId: id },
		request: new Request('http://localhost/api/jafar/prospects/' + id + '/reverse-payment', {
			method: 'POST',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		url: new URL('http://localhost/api/jafar/prospects/' + id + '/reverse-payment'),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

function clientWith(
	applicationResult: { data: unknown; error: null | { message: string } } = {
		data: { business_name: 'Bright Co' },
		error: null
	},
	rpcError: { message: string } | null = null
) {
	const rpc = vi.fn().mockResolvedValue({ error: rpcError });
	const from = vi.fn().mockReturnValue({
		select: () => ({
			eq: () => ({
				maybeSingle: () => Promise.resolve(applicationResult)
			})
		})
	});
	return { rpc, from, __rpc: rpc };
}

describe('platform owner prospect payment reversal API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRaiseAlert.mockResolvedValue('notification-1');
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);
		const response = await POST(event(prospectId));
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the prospect identifier before database access', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const response = await POST(event('not-a-uuid'));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires a reason', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const response = await POST(event(prospectId, { reason: '  ' }));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the prospect does not exist', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(clientWith({ data: null, error: null }) as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(404);
	});

	it('rejects when the application is not in a reversible stage', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith(undefined, {
				message: 'Only a confirmed payment can be reversed.'
			}) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
	});

	it('rejects when the payment was already reversed', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith(undefined, { message: 'This payment was already reversed.' }) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
	});

	it('rejects when there is no payment confirmation on file', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith(undefined, {
				message: 'No payment confirmation exists for this application.'
			}) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
	});

	it('reverses the payment, raises an urgent alert, and returns ok', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const client = clientWith();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ ok: true });
		expect(client.__rpc).toHaveBeenCalledWith('reverse_onboarding_application_payment', {
			target_application_id: prospectId,
			actor_email: 'owner@example.com',
			reason: validBody.reason
		});
		expect(mockedRaiseAlert).toHaveBeenCalledWith(
			client,
			expect.objectContaining({
				kind: 'onboarding_application_payment_reversed',
				severity: 'urgent',
				title: 'Payment reversed for Bright Co',
				body: validBody.reason,
				target: { targetKind: 'onboarding_application', targetId: prospectId }
			})
		);
	});

	it('still succeeds when raising the alert fails', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const client = clientWith();
		mockedClient.mockReturnValue(client as never);
		mockedRaiseAlert.mockRejectedValueOnce(new Error('Brevo is down'));

		const response = await POST(event(prospectId));
		expect(response.status).toBe(200);
	});

	it('returns a safe server error when the reversal cannot be saved', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith(undefined, { message: 'internal database details' }) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'The payment could not be reversed.' });
	});
});
