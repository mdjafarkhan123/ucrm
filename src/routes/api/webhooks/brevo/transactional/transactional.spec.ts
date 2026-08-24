import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$env/dynamic/private', () => ({
	env: { BREVO_TRANSACTIONAL_WEBHOOK_TOKEN: 'transactional-webhook-token' }
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const intentId = '00000000-0000-4000-8000-000000000042';

function eventWith(body: unknown, authorization?: string) {
	return {
		request: new Request('https://app.example.com/api/webhooks/brevo/transactional', {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
				...(authorization ? { authorization } : {})
			},
			body: typeof body === 'string' ? body : JSON.stringify(body)
		})
	} as Parameters<typeof POST>[0];
}

function clientWith(result: { error: { code?: string } | null }) {
	const insert = vi.fn().mockResolvedValue(result);
	return { from: vi.fn(() => ({ insert })), insert };
}

describe('Brevo transactional callback route', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects requests before attempting a privileged write', async () => {
		const response = await POST(eventWith({ event: 'delivered' }));

		expect(response.status).toBe(401);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('records the provider event with a stable key and UCRM intent reference', async () => {
		const client = clientWith({ error: null });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			eventWith(
				{
					event: 'delivered',
					id: 9,
					['message-id']: 'provider-message-9',
					ts_event: 1_700_000_000,
					tags: [`ucrm:email:${intentId}`]
				},
				'Bearer transactional-webhook-token'
			)
		);

		expect(response.status).toBe(200);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(client.from).toHaveBeenCalledWith('communication_provider_callback_events');
		expect(client.insert).toHaveBeenCalledWith(
			expect.objectContaining({
				provider_event_key: 'delivered:9:provider-message-9:1700000000',
				delivery_intent_id: intentId,
				event_kind: 'delivered'
			})
		);
		expect(await response.json()).toEqual({ accepted: true });
	});

	it('treats a duplicate provider event as accepted without creating a retry loop', async () => {
		const client = clientWith({ error: { code: '23505' } });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			eventWith({ event: 'delivered', id: 9 }, 'Bearer transactional-webhook-token')
		);

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ accepted: true, duplicate: true });
	});
});
