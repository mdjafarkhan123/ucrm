import { describe, expect, it, vi } from 'vitest';

vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: () => ({}) }));

const { drainMessengerWebhookEvents } = await import('./messenger-inbound-worker');
type Client = NonNullable<Parameters<typeof drainMessengerWebhookEvents>[0]>['client'] & object;

const delivery = (pageId: string, mids: string[]) => ({
	object: 'page',
	entry: [
		{
			id: pageId,
			messaging: mids.map((mid) => ({
				sender: { id: '7001' },
				recipient: { id: pageId },
				timestamp: 1_790_000_000_000,
				message: { mid, text: mid }
			}))
		}
	]
});

function fakeClient(
	events: { id: string; payload: unknown }[],
	connections: Record<string, string>
) {
	const queue = events.map((event) => ({ ...event, claim_token: `claim-${event.id}` }));
	const client = {
		claim: vi.fn(async (limit: number) => ({ data: queue.splice(0, limit), error: null })),
		findConnectionId: vi.fn(async (pageId: string) => ({
			data: connections[pageId] ?? null,
			error: null
		})),
		recordMessage: vi.fn(async () => ({ error: null as { message: string } | null })),
		recordEcho: vi.fn(async () => ({ error: null as { message: string } | null })),
		recordReceipt: vi.fn(async () => ({ error: null as { message: string } | null })),
		finish: vi.fn(async () => ({ error: null }))
	};
	return client satisfies Client;
}

describe('drainMessengerWebhookEvents', () => {
	it('bounds a local burst to 200 deliveries per wake and leaves the remainder for the next wake', async () => {
		const events = Array.from({ length: 225 }, (_, index) => ({
			id: `burst-${index}`,
			payload: delivery(index % 2 ? '9001' : '9002', [`repeated-${index % 10}`])
		}));
		const client = fakeClient(events, { '9001': 'conn-1', '9002': 'conn-2' });
		expect(await drainMessengerWebhookEvents({ client })).toEqual({
			claimed: 200,
			processed: 200,
			failed: 0
		});
		expect(client.recordMessage).toHaveBeenCalledTimes(200);
		expect(await drainMessengerWebhookEvents({ client })).toEqual({
			claimed: 25,
			processed: 25,
			failed: 0
		});
		expect(client.recordMessage).toHaveBeenCalledTimes(225);
	});

	it('records each customer message against the Page’s connection and marks the delivery done', async () => {
		const client = fakeClient([{ id: 'e1', payload: delivery('9001', ['m_1', 'm_2']) }], {
			'9001': 'conn-1'
		});
		const result = await drainMessengerWebhookEvents({ client });

		expect(result).toEqual({ claimed: 1, processed: 1, failed: 0 });
		expect(client.recordMessage).toHaveBeenCalledTimes(2);
		expect(client.recordMessage).toHaveBeenCalledWith(
			expect.objectContaining({
				target_connection_id: 'conn-1',
				target_psid: '7001',
				target_mid: 'm_1'
			})
		);
		expect(client.findConnectionId).toHaveBeenCalledOnce();
		expect(client.finish).toHaveBeenCalledWith('e1', 'claim-e1', null);
	});

	it('keeps a delivery for a Page nobody connected as done without recording anything', async () => {
		const client = fakeClient([{ id: 'e1', payload: delivery('9999', ['m_1']) }], {});
		const result = await drainMessengerWebhookEvents({ client });

		expect(result.processed).toBe(1);
		expect(client.recordMessage).not.toHaveBeenCalled();
		expect(client.finish).toHaveBeenCalledWith('e1', 'claim-e1', null);
	});

	it('leaves a failed delivery for retry with its reason and carries on with the next', async () => {
		const client = fakeClient(
			[
				{ id: 'e1', payload: delivery('9001', ['m_1']) },
				{ id: 'e2', payload: delivery('9001', ['m_2']) }
			],
			{ '9001': 'conn-1' }
		);
		client.recordMessage.mockResolvedValueOnce({ error: { message: 'database down' } });
		const logged = vi.spyOn(console, 'error').mockImplementation(() => {});
		const result = await drainMessengerWebhookEvents({ client });
		logged.mockRestore();

		expect(result).toEqual({ claimed: 2, processed: 1, failed: 1 });
		expect(client.finish).toHaveBeenCalledWith(
			'e1',
			'claim-e1',
			expect.stringContaining('database down')
		);
		expect(client.finish).toHaveBeenCalledWith('e2', 'claim-e2', null);
	});

	it('keeps claiming while full batches come back', async () => {
		const events = Array.from({ length: 5 }, (_, index) => ({
			id: `e${index}`,
			payload: delivery('9001', [`m_${index}`])
		}));
		const client = fakeClient(events, { '9001': 'conn-1' });
		const result = await drainMessengerWebhookEvents({ client, batchSize: 2 });

		expect(result.claimed).toBe(5);
		expect(client.claim).toHaveBeenCalledTimes(3);
	});

	it('records echoes as ours or from the Page’s own inbox, and delivered/read watermarks', async () => {
		const payload = {
			object: 'page',
			entry: [
				{
					id: '9001',
					messaging: [
						{
							sender: { id: '9001' },
							recipient: { id: '7001' },
							timestamp: 1_790_000_000_000,
							message: {
								mid: 'm_ours',
								is_echo: true,
								app_id: 555,
								metadata: 'intent-1',
								text: 'Hi'
							}
						},
						{
							sender: { id: '9001' },
							recipient: { id: '7001' },
							timestamp: 1_790_000_001_000,
							message: {
								mid: 'm_fb',
								is_echo: true,
								app_id: 263902037430900,
								text: 'From Facebook'
							}
						},
						{
							sender: { id: '7001' },
							recipient: { id: '9001' },
							delivery: { watermark: 1_790_000_002_000, mids: ['m_ours'] }
						},
						{
							sender: { id: '7001' },
							recipient: { id: '9001' },
							read: { watermark: 1_790_000_003_000 }
						}
					]
				}
			]
		};
		const client = fakeClient([{ id: 'e1', payload }], { '9001': 'conn-1' });
		const result = await drainMessengerWebhookEvents({ client, ourAppId: '555' });

		expect(result).toEqual({ claimed: 1, processed: 1, failed: 0 });
		expect(client.recordMessage).not.toHaveBeenCalled();
		expect(client.recordEcho).toHaveBeenCalledWith(
			expect.objectContaining({
				target_mid: 'm_ours',
				target_metadata: 'intent-1',
				target_from_this_app: true
			})
		);
		expect(client.recordEcho).toHaveBeenCalledWith(
			expect.objectContaining({
				target_mid: 'm_fb',
				target_text: 'From Facebook',
				target_from_this_app: false
			})
		);
		expect(client.recordReceipt).toHaveBeenCalledWith({
			target_connection_id: 'conn-1',
			target_psid: '7001',
			target_kind: 'delivered',
			target_watermark: new Date(1_790_000_002_000).toISOString(),
			target_mids: ['m_ours']
		});
		expect(client.recordReceipt).toHaveBeenCalledWith(
			expect.objectContaining({ target_kind: 'read', target_mids: [] })
		);
	});
});
