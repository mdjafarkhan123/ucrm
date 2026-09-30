import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const prospectId = '123e4567-e89b-12d3-a456-426614174000';
const editionId = '223e4567-e89b-12d3-a456-426614174000';
const validBody = {
	edition_id: editionId,
	billing_interval: 'year',
	reason: 'Agreed yearly on the call'
};

function event(id: string, body: unknown = validBody) {
	return {
		params: { prospectId: id },
		request: new Request('http://localhost/api/jafar/prospects/' + id + '/correct-package', {
			method: 'POST',
			body: JSON.stringify(body)
		}),
		url: new URL('http://localhost/api/jafar/prospects/' + id + '/correct-package'),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function clientWith(rpcError: { message: string } | null = null) {
	return { rpc: vi.fn().mockResolvedValue({ data: null, error: rpcError }) };
}

describe('platform owner prospect package correction API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		} as never);
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		expect((await POST(event(prospectId))).status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires a package, a billing interval, and a reason', async () => {
		const response = await POST(
			event(prospectId, { edition_id: 'x', billing_interval: 'week', reason: '' })
		);
		expect(response.status).toBe(422);
		const body = (await response.json()) as { field_errors: Record<string, string> };
		expect(Object.keys(body.field_errors)).toEqual(
			expect.arrayContaining(['edition_id', 'billing_interval', 'reason'])
		);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('moves the application to the chosen edition and billing with the reason', async () => {
		const client = clientWith();
		mockedClient.mockReturnValue(client as never);
		expect((await POST(event(prospectId))).status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith('correct_onboarding_application_package', {
			target_application_id: prospectId,
			actor_email: 'owner@example.com',
			new_edition_id: editionId,
			new_billing_interval: 'year',
			correction_reason: 'Agreed yearly on the call'
		});
	});

	it('refuses after payment is confirmed', async () => {
		mockedClient.mockReturnValue(
			clientWith({
				message:
					'The package can no longer be changed after payment is confirmed. Reverse the payment first.'
			}) as never
		);
		expect((await POST(event(prospectId))).status).toBe(409);
	});

	it('puts a missing yearly price on the billing field', async () => {
		mockedClient.mockReturnValue(
			clientWith({
				message: 'The selected package has no yearly price. Choose the other billing.'
			}) as never
		);
		const response = await POST(event(prospectId));
		expect(response.status).toBe(422);
		const body = (await response.json()) as { field_errors: Record<string, string> };
		expect(body.field_errors.billing_interval).toContain('no yearly price');
	});
});
