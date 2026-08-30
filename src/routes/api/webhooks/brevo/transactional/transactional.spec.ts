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
	const rpc = vi.fn().mockResolvedValue({ error: null });
	return { from: vi.fn(() => ({ insert })), insert, rpc };
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
		// R1: the intent's status is flipped on arrival via a small bounded drain, so an open inbox shows
		// delivered/bounced without waiting for the cron.
		expect(client.rpc).toHaveBeenCalledWith('process_communication_provider_callbacks', {
			batch_size: 25
		});
	});

	it('still accepts the event when on-arrival processing fails', async () => {
		const client = clientWith({ error: null });
		client.rpc.mockResolvedValue({ error: { code: '57014' } });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			eventWith({ event: 'delivered', id: 9 }, 'Bearer transactional-webhook-token')
		);

		// The durable insert already succeeded; a drain failure is swallowed and the cron catches up.
		expect(response.status).toBe(200);
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
		// A duplicate returns before the drain: nothing new to process.
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('asks the provider to retry when the event could not be durably stored', async () => {
		const client = clientWith({ error: { code: '08006' } });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			eventWith({ event: 'hard_bounce', id: 9 }, 'Bearer transactional-webhook-token')
		);

		expect(response.status).toBe(429);
		expect(response.headers.get('retry-after')).toBe('60');
		expect(response.headers.get('cache-control')).toBe('no-store');
	});
});
