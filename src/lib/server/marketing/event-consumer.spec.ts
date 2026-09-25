import { describe, expect, it, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: {} }));

const { raiseOwnerAlert } = vi.hoisted(() => ({
	raiseOwnerAlert: vi.fn(async () => 'notification-id')
}));
vi.mock('$lib/server/jafar/owner-alerts', () => ({ raiseOwnerAlert }));

import {
	drainMarketingEventQueue,
	runMonitoredMarketingEventsWake,
	type DlqClientLike,
	type MarketingEventsWorkerClient,
	type SqsClientLike,
	type SqsMessage
} from './event-consumer';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';

const deliveredMessage: SqsMessage = {
	receiptHandle: 'receipt-1',
	body: JSON.stringify({
		eventType: 'Delivery',
		mail: { messageId: 'msg-1', timestamp: '2026-09-22T10:00:00.000Z' },
		delivery: {}
	})
};

function operationalDeliveredMessage(
	overrides: { intentId?: string | null; receiptHandle?: string } = {}
): SqsMessage {
	const intentId = overrides.intentId === undefined ? 'intent-1' : overrides.intentId;
	return {
		receiptHandle: overrides.receiptHandle ?? 'receipt-op-1',
		body: JSON.stringify({
			eventType: 'Delivery',
			mail: {
				messageId: 'msg-op-1',
				timestamp: '2026-09-22T10:00:00.000Z',
				tags: {
					'ses:configuration-set': ['ucrm-operational-raad'],
					...(intentId ? { 'ucrm-intent': [intentId] } : {})
				}
			},
			delivery: {}
		})
	};
}

function fakeClient(overrides: Partial<MarketingEventsWorkerClient> = {}): {
	client: MarketingEventsWorkerClient;
	rpc: ReturnType<typeof vi.fn>;
	insertEvent: ReturnType<typeof vi.fn>;
	insertCallbackEvent: ReturnType<typeof vi.fn>;
} {
	const rpc = vi.fn(async (name: string) => {
		if (name === 'project_marketing_campaign_recipient_events') return { data: 0, error: null };
		if (name === 'process_communication_provider_callbacks') return { data: 0, error: null };
		return { data: null, error: { message: `Unexpected RPC ${name}.` } };
	});
	const insertEvent = vi.fn(async () => ({ error: null }));
	const insertCallbackEvent = vi.fn(async () => ({ error: null }));
	return {
		client: { rpc, insertEvent, insertCallbackEvent, ...overrides } as MarketingEventsWorkerClient,
		rpc,
		insertEvent,
		insertCallbackEvent
	};
}

function fakeSqs(batches: SqsMessage[][]): { sqs: SqsClientLike; removed: string[] } {
	const removed: string[] = [];
	let call = 0;
	const sqs: SqsClientLike = {
		async receive() {
			const batch = batches[call] ?? [];
			call += 1;
			return batch;
		},
		async remove(receiptHandle) {
			removed.push(receiptHandle);
		}
	};
	return { sqs, removed };
}

describe('drainMarketingEventQueue', () => {
	it('records a valid message, deletes it, and stops idle once the queue is empty', async () => {
		const { client, insertEvent, rpc } = fakeClient();
		const { sqs, removed } = fakeSqs([[deliveredMessage], []]);

		const result = await drainMarketingEventQueue({ client, sqs });

		expect(result).toMatchObject({
			received: 1,
			recorded: 1,
			duplicates: 0,
			skipped: 0,
			stoppedBy: 'idle'
		});
		expect(insertEvent).toHaveBeenCalledWith({
			provider_event_key: 'ses:msg-1:Delivery',
			provider_message_id: 'msg-1',
			event_kind: 'Delivery',
			occurred_at: '2026-09-22T10:00:00.000Z',
			payload: expect.objectContaining({ eventType: 'Delivery' })
		});
		expect(removed).toEqual(['receipt-1']);
		expect(rpc).toHaveBeenCalledWith('project_marketing_campaign_recipient_events', {
			batch_size: 200
		});
		expect(rpc).toHaveBeenCalledWith('process_communication_provider_callbacks', {
			batch_size: 200
		});
	});

	it('routes an operational configuration-set event to insertCallbackEvent, not insertEvent', async () => {
		const { client, insertEvent, insertCallbackEvent } = fakeClient();
		const { sqs, removed } = fakeSqs([[operationalDeliveredMessage()], []]);

		const result = await drainMarketingEventQueue({ client, sqs });

		expect(result).toMatchObject({ received: 1, recorded: 1, ignored: 0, skipped: 0 });
		expect(insertCallbackEvent).toHaveBeenCalledWith({
			provider_event_key: 'ses:msg-op-1:Delivery',
			delivery_intent_id: 'intent-1',
			event_kind: 'delivered',
			occurred_at: '2026-09-22T10:00:00.000Z',
			payload: expect.objectContaining({ eventType: 'Delivery' })
		});
		expect(insertEvent).not.toHaveBeenCalled();
		expect(removed).toEqual(['receipt-op-1']);
	});

	it('swallows a 23503 on an operational callback insert as ignored and deletes the message', async () => {
		const { client } = fakeClient({
			insertCallbackEvent: vi.fn(async () => ({
				error: { code: '23503', message: 'foreign key violation' }
			}))
		});
		const { sqs, removed } = fakeSqs([[operationalDeliveredMessage()], []]);

		const result = await drainMarketingEventQueue({ client, sqs });

		expect(result).toMatchObject({ received: 1, recorded: 0, ignored: 1, skipped: 0 });
		expect(removed).toEqual(['receipt-op-1']);
	});

	it('calls process_communication_provider_callbacks once per drain', async () => {
		const { client, rpc } = fakeClient();
		const { sqs } = fakeSqs([[operationalDeliveredMessage()], []]);

		await drainMarketingEventQueue({ client, sqs });

		expect(
			rpc.mock.calls.filter(([name]) => name === 'process_communication_provider_callbacks')
		).toHaveLength(1);
	});

	it('deletes a duplicate message without re-throwing', async () => {
		const { client } = fakeClient({
			insertEvent: vi.fn(async () => ({ error: { code: '23505', message: 'duplicate key' } }))
		});
		const { sqs, removed } = fakeSqs([[deliveredMessage], []]);

		const result = await drainMarketingEventQueue({ client, sqs });

		expect(result).toMatchObject({ received: 1, recorded: 0, duplicates: 1 });
		expect(removed).toEqual(['receipt-1']);
	});

	it('deletes the SNS topic-validation confirmation without recording or dead-lettering it', async () => {
		const { client, insertEvent } = fakeClient();
		const confirmation: SqsMessage = {
			receiptHandle: 'receipt-confirmation',
			body: 'Successfully validated SNS topic for Amazon SES event publishing.'
		};
		const { sqs, removed } = fakeSqs([[confirmation], []]);

		const result = await drainMarketingEventQueue({ client, sqs });

		expect(result).toMatchObject({ received: 1, recorded: 0, ignored: 1, skipped: 0 });
		expect(insertEvent).not.toHaveBeenCalled();
		expect(removed).toEqual(['receipt-confirmation']);
	});

	it('leaves an unparseable message undeleted for the DLQ policy', async () => {
		const { client, insertEvent } = fakeClient();
		const badMessage: SqsMessage = { receiptHandle: 'receipt-bad', body: 'not json' };
		const { sqs, removed } = fakeSqs([[badMessage], []]);

		const result = await drainMarketingEventQueue({ client, sqs });

		expect(result).toMatchObject({ received: 1, recorded: 0, skipped: 1 });
		expect(insertEvent).not.toHaveBeenCalled();
		expect(removed).toEqual([]);
	});

	it('leaves a message that does not match the SES event shape undeleted', async () => {
		const { client } = fakeClient();
		const wrongShape: SqsMessage = {
			receiptHandle: 'receipt-2',
			body: JSON.stringify({ hello: 'world' })
		};
		const { sqs, removed } = fakeSqs([[wrongShape], []]);

		const result = await drainMarketingEventQueue({ client, sqs });

		expect(result).toMatchObject({ received: 1, recorded: 0, skipped: 1 });
		expect(removed).toEqual([]);
	});

	it('throws and does not delete when a non-duplicate insert error occurs', async () => {
		const { client } = fakeClient({
			insertEvent: vi.fn(async () => ({ error: { message: 'storage failure' } }))
		});
		const { sqs, removed } = fakeSqs([[deliveredMessage]]);

		await expect(drainMarketingEventQueue({ client, sqs })).rejects.toThrow(/storage failure/);
		expect(removed).toEqual([]);
	});

	it('stops at max_messages once the bound is reached', async () => {
		const { client } = fakeClient();
		const { sqs } = fakeSqs([[deliveredMessage], [deliveredMessage], [deliveredMessage]]);

		const result = await drainMarketingEventQueue({
			client,
			sqs,
			maxMessages: 1,
			receiveBatchSize: 1
		});

		expect(result).toMatchObject({ received: 1, stoppedBy: 'max_messages' });
	});

	it('stops at time_budget once the deadline passes', async () => {
		const { client } = fakeClient();
		const { sqs } = fakeSqs([[deliveredMessage], [deliveredMessage]]);
		let clock = 0;
		const now = () => {
			clock += 15_000;
			return clock;
		};

		const result = await drainMarketingEventQueue({ client, sqs, timeBudgetMs: 10_000, now });

		expect(result.stoppedBy).toBe('time_budget');
	});
});

describe('runMonitoredMarketingEventsWake', () => {
	it('reports already_running when the lease cannot be acquired', async () => {
		const rpc = vi.fn(async (name: string) => {
			if (name === 'acquire_communication_worker_lease') return { data: null, error: null };
			if (name === 'record_communication_worker_wake_result') return { data: null, error: null };
			return { data: null, error: { message: `Unexpected RPC ${name}.` } };
		});
		const client = { rpc, insertEvent: vi.fn() } as unknown as MarketingEventsWorkerClient;

		const result = await runMonitoredMarketingEventsWake({ wakeCorrelationId: 'wake-1', client });

		expect(result).toEqual({ outcome: 'already_running' });
	});

	it('drains, records the result, and releases the lease on the happy path', async () => {
		const rpcCalls: string[] = [];
		const rpc = vi.fn(async (name: string) => {
			rpcCalls.push(name);
			if (name === 'acquire_communication_worker_lease')
				return { data: 'lease-token', error: null };
			if (name === 'release_communication_worker_lease') return { data: null, error: null };
			if (name === 'record_communication_worker_wake_result') return { data: null, error: null };
			if (name === 'project_marketing_campaign_recipient_events') return { data: 0, error: null };
			if (name === 'process_communication_provider_callbacks') return { data: 0, error: null };
			return { data: null, error: { message: `Unexpected RPC ${name}.` } };
		});
		const client = {
			rpc,
			insertEvent: vi.fn(async () => ({ error: null })),
			insertCallbackEvent: vi.fn(async () => ({ error: null }))
		} as MarketingEventsWorkerClient;
		const { sqs } = fakeSqs([[]]);

		const result = await runMonitoredMarketingEventsWake({
			wakeCorrelationId: 'wake-2',
			client,
			sqs
		});

		expect(result.outcome).toBe('idle');
		expect(rpcCalls).toContain('acquire_communication_worker_lease');
		expect(rpcCalls).toContain('release_communication_worker_lease');
		expect(rpcCalls).toContain('record_communication_worker_wake_result');
	});

	it('records an error outcome and releases the lease when the drain throws', async () => {
		const rpc = vi.fn(async (name: string) => {
			if (name === 'acquire_communication_worker_lease')
				return { data: 'lease-token', error: null };
			if (name === 'release_communication_worker_lease') return { data: null, error: null };
			if (name === 'record_communication_worker_wake_result') return { data: null, error: null };
			return { data: null, error: { message: `Unexpected RPC ${name}.` } };
		});
		const client = {
			rpc,
			insertEvent: vi.fn(async () => ({ error: { message: 'boom' } }))
		} as unknown as MarketingEventsWorkerClient;
		const { sqs } = fakeSqs([[deliveredMessage]]);

		await expect(
			runMonitoredMarketingEventsWake({ wakeCorrelationId: 'wake-3', client, sqs })
		).rejects.toThrow(/boom/);
		expect(rpc).toHaveBeenCalledWith(
			'record_communication_worker_wake_result',
			expect.objectContaining({ p_route_outcome: 'error' })
		);
	});

	function happyClient() {
		const rpc = vi.fn(async (name: string) => {
			if (name === 'acquire_communication_worker_lease')
				return { data: 'lease-token', error: null };
			if (name === 'release_communication_worker_lease') return { data: null, error: null };
			if (name === 'record_communication_worker_wake_result') return { data: null, error: null };
			if (name === 'project_marketing_campaign_recipient_events') return { data: 0, error: null };
			if (name === 'process_communication_provider_callbacks') return { data: 0, error: null };
			return { data: null, error: { message: `Unexpected RPC ${name}.` } };
		});
		return {
			rpc,
			insertEvent: vi.fn(async () => ({ error: null })),
			insertCallbackEvent: vi.fn(async () => ({ error: null }))
		} as MarketingEventsWorkerClient;
	}

	function fakeOwner(recentRows: unknown[]): SupabaseClient<Database> {
		const query = {
			select: () => query,
			eq: () => query,
			is: () => query,
			gte: () => query,
			limit: async () => ({ data: recentRows, error: null })
		};
		return { from: () => query } as unknown as SupabaseClient<Database>;
	}

	function fakeDlq(depth: number): DlqClientLike {
		return { approximateDepth: vi.fn(async () => depth) };
	}

	it('alerts when the dead-letter queue holds messages and no recent alert is unread', async () => {
		raiseOwnerAlert.mockClear();
		const { sqs } = fakeSqs([[]]);
		const owner = fakeOwner([]);

		await runMonitoredMarketingEventsWake({
			wakeCorrelationId: 'wake-dlq-1',
			client: happyClient(),
			sqs,
			dlq: fakeDlq(3),
			owner
		});

		expect(raiseOwnerAlert).toHaveBeenCalledTimes(1);
		expect(raiseOwnerAlert).toHaveBeenCalledWith(
			owner,
			expect.objectContaining({ kind: 'marketing_ses_dlq_message', severity: 'urgent' })
		);
	});

	it('does not alert again while an unread alert from the last day still stands', async () => {
		raiseOwnerAlert.mockClear();
		const { sqs } = fakeSqs([[]]);
		const owner = fakeOwner([{ id: 'existing-notification' }]);

		await runMonitoredMarketingEventsWake({
			wakeCorrelationId: 'wake-dlq-2',
			client: happyClient(),
			sqs,
			dlq: fakeDlq(3),
			owner
		});

		expect(raiseOwnerAlert).not.toHaveBeenCalled();
	});

	it('does not alert when the dead-letter queue is empty', async () => {
		raiseOwnerAlert.mockClear();
		const { sqs } = fakeSqs([[]]);
		const owner = fakeOwner([]);

		await runMonitoredMarketingEventsWake({
			wakeCorrelationId: 'wake-dlq-3',
			client: happyClient(),
			sqs,
			dlq: fakeDlq(0),
			owner
		});

		expect(raiseOwnerAlert).not.toHaveBeenCalled();
	});
});
