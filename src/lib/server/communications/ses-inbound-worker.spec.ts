import { describe, expect, it, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: {} }));

const { raiseOwnerAlert } = vi.hoisted(() => ({
	raiseOwnerAlert: vi.fn(async () => 'notification-id')
}));
vi.mock('$lib/server/jafar/owner-alerts', () => ({ raiseOwnerAlert }));

import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	drainSesInboundQueue,
	runMonitoredSesInboundWake,
	type DlqClientLike,
	type SesInboundWorkerClient,
	type SqsClientLike,
	type SqsMessage
} from './ses-inbound-worker';

const validNotification = {
	notificationType: 'Received',
	mail: { messageId: 'ses-msg-1', timestamp: '2026-09-25T10:00:00.000Z' },
	receipt: {
		recipients: ['r_abc@reply.example.com'],
		action: { type: 'S3', bucketName: 'ucrm-ses-inbound-mime', objectKey: 'org-1/ses-msg-1' }
	}
};

const validMessage: SqsMessage = {
	receiptHandle: 'receipt-1',
	body: JSON.stringify(validNotification)
};

const plainTextMime = Buffer.from(
	[
		'From: jane@example.com',
		'To: r_abc@reply.example.com',
		'Subject: Re: quote',
		'Content-Type: text/plain; charset=utf-8',
		'',
		'Sounds good.'
	].join('\r\n')
);

function fakeClient(overrides: Partial<SesInboundWorkerClient> = {}): {
	client: SesInboundWorkerClient;
	rpc: ReturnType<typeof vi.fn>;
	insertCallbackEvent: ReturnType<typeof vi.fn>;
	insertAttachments: ReturnType<typeof vi.fn>;
} {
	const rpc = vi.fn(async (name: string) => {
		if (name === 'record_communication_inbound_message')
			return { data: { id: 'message-1', organization_id: 'org-1' }, error: null };
		return { data: null, error: { message: `Unexpected RPC ${name}.` } };
	});
	const insertCallbackEvent = vi.fn(async () => ({ data: { id: 'callback-1' }, error: null }));
	const insertAttachments = vi.fn(async () => ({ error: null }));
	const findCallbackEventId = vi.fn(async () => ({ data: null, error: null }));
	return {
		client: {
			rpc,
			insertCallbackEvent,
			findCallbackEventId,
			insertAttachments,
			...overrides
		} as SesInboundWorkerClient,
		rpc,
		insertCallbackEvent,
		insertAttachments
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

const fetchObject = vi.fn(async () => plainTextMime);

describe('drainSesInboundQueue', () => {
	it('records a valid message, deletes it, and stops idle once the queue is empty', async () => {
		const { client, insertCallbackEvent, rpc } = fakeClient();
		const { sqs, removed } = fakeSqs([[validMessage], []]);

		const result = await drainSesInboundQueue({ client, sqs, fetchObject });

		expect(result).toMatchObject({
			received: 1,
			recorded: 1,
			duplicates: 0,
			invalid: 0,
			stoppedBy: 'idle'
		});
		expect(insertCallbackEvent).toHaveBeenCalledWith({
			provider_event_key: 'ses-inbound:ses-msg-1',
			event_kind: 'inbound_email',
			occurred_at: '2026-09-25T10:00:00.000Z',
			payload: expect.objectContaining({ notificationType: 'Received' })
		});
		expect(rpc).toHaveBeenCalledWith(
			'record_communication_inbound_message',
			expect.objectContaining({
				target_provider_message_id: 'ses-msg-1',
				target_sender_email: 'jane@example.com',
				target_provider: 'ses'
			})
		);
		expect(removed).toEqual(['receipt-1']);
	});

	const alreadyLogged = {
		insertCallbackEvent: vi.fn(async () => ({
			data: null,
			error: { code: '23505', message: 'duplicate key' }
		})),
		findCallbackEventId: vi.fn(async () => ({ data: { id: 'callback-1' }, error: null }))
	};

	it('files a redelivered reply whose earlier attempt logged the callback but failed before filing', async () => {
		const { client, rpc } = fakeClient(alreadyLogged);
		const { sqs, removed } = fakeSqs([[validMessage], []]);

		const result = await drainSesInboundQueue({ client, sqs, fetchObject });

		expect(result).toMatchObject({ received: 1, recorded: 1, duplicates: 0 });
		expect(rpc).toHaveBeenCalledWith(
			'record_communication_inbound_message',
			expect.objectContaining({ target_provider_callback_event_id: 'callback-1' })
		);
		expect(removed).toEqual(['receipt-1']);
	});

	it('deletes a redelivered reply as a duplicate once it is already filed', async () => {
		const { client, insertAttachments } = fakeClient({
			...alreadyLogged,
			rpc: vi.fn(async () => ({ data: null, error: null }))
		});
		const { sqs, removed } = fakeSqs([[validMessage], []]);

		const result = await drainSesInboundQueue({ client, sqs, fetchObject });

		expect(result).toMatchObject({ received: 1, recorded: 0, duplicates: 1 });
		expect(insertAttachments).not.toHaveBeenCalled();
		expect(removed).toEqual(['receipt-1']);
	});

	it('leaves an unparseable message body undeleted for the DLQ policy', async () => {
		const { client } = fakeClient();
		const badMessage: SqsMessage = { receiptHandle: 'receipt-bad', body: 'not json' };
		const { sqs, removed } = fakeSqs([[badMessage], []]);

		const result = await drainSesInboundQueue({ client, sqs, fetchObject });

		expect(result).toMatchObject({ received: 1, recorded: 0, invalid: 1 });
		expect(removed).toEqual([]);
	});

	it('leaves a message undeleted when fetching the S3 object fails', async () => {
		const { client } = fakeClient();
		const { sqs, removed } = fakeSqs([[validMessage], []]);
		const failingFetch = vi.fn(async () => {
			throw new Error('S3 access denied');
		});

		const result = await drainSesInboundQueue({ client, sqs, fetchObject: failingFetch });

		expect(result).toMatchObject({ received: 1, recorded: 0, invalid: 1 });
		expect(removed).toEqual([]);
	});

	it('throws and does not delete when record_communication_inbound_message errors', async () => {
		const { client } = fakeClient({
			rpc: vi.fn(async () => ({ data: null, error: { message: 'db down' } }))
		});
		const { sqs, removed } = fakeSqs([[validMessage]]);

		await expect(drainSesInboundQueue({ client, sqs, fetchObject })).rejects.toThrow(/db down/);
		expect(removed).toEqual([]);
	});

	it('records an attachment row when the parsed message has one', async () => {
		const { client, insertAttachments } = fakeClient();
		const { sqs } = fakeSqs([[validMessage], []]);
		const withAttachmentMime = Buffer.from(
			[
				'From: jane@example.com',
				'To: r_abc@reply.example.com',
				'Subject: See attached',
				'Content-Type: multipart/mixed; boundary="B"',
				'',
				'--B',
				'Content-Type: text/plain',
				'',
				'hi',
				'--B',
				'Content-Type: image/jpeg',
				'Content-Disposition: attachment; filename="photo.jpg"',
				'Content-Transfer-Encoding: base64',
				'',
				Buffer.from('bytes').toString('base64'),
				'--B--',
				''
			].join('\r\n')
		);

		await drainSesInboundQueue({
			client,
			sqs,
			fetchObject: vi.fn(async () => withAttachmentMime)
		});

		expect(insertAttachments).toHaveBeenCalledWith([
			expect.objectContaining({
				organization_id: 'org-1',
				inbound_message_id: 'message-1',
				file_name: 'photo.jpg',
				provider: 'ses',
				status: 'pending_import',
				provider_download_token: 'org-1/ses-msg-1#0'
			})
		]);
	});

	it('stops at max_messages once the bound is reached', async () => {
		const { client } = fakeClient();
		const { sqs } = fakeSqs([[validMessage], [validMessage], [validMessage]]);

		const result = await drainSesInboundQueue({
			client,
			sqs,
			fetchObject,
			maxMessages: 1,
			receiveBatchSize: 1
		});

		expect(result).toMatchObject({ received: 1, stoppedBy: 'max_messages' });
	});

	it('stops at time_budget once the deadline passes', async () => {
		const { client } = fakeClient();
		const { sqs } = fakeSqs([[validMessage], [validMessage]]);
		let clock = 0;
		const now = () => {
			clock += 15_000;
			return clock;
		};

		const result = await drainSesInboundQueue({
			client,
			sqs,
			fetchObject,
			timeBudgetMs: 10_000,
			now
		});

		expect(result.stoppedBy).toBe('time_budget');
	});
});

describe('runMonitoredSesInboundWake', () => {
	it('reports already_running when the lease cannot be acquired', async () => {
		const rpc = vi.fn(async (name: string) => {
			if (name === 'acquire_communication_worker_lease') return { data: null, error: null };
			if (name === 'record_communication_worker_wake_result') return { data: null, error: null };
			return { data: null, error: { message: `Unexpected RPC ${name}.` } };
		});
		const client = {
			rpc,
			insertCallbackEvent: vi.fn(),
			insertAttachments: vi.fn()
		} as unknown as SesInboundWorkerClient;

		const result = await runMonitoredSesInboundWake({ wakeCorrelationId: 'wake-1', client });

		expect(result).toEqual({ outcome: 'already_running' });
	});

	function happyClient() {
		const rpc = vi.fn(async (name: string) => {
			if (name === 'acquire_communication_worker_lease')
				return { data: 'lease-token', error: null };
			if (name === 'release_communication_worker_lease') return { data: null, error: null };
			if (name === 'record_communication_worker_wake_result') return { data: null, error: null };
			return { data: null, error: { message: `Unexpected RPC ${name}.` } };
		});
		return {
			rpc,
			insertCallbackEvent: vi.fn(),
			insertAttachments: vi.fn()
		} as unknown as SesInboundWorkerClient;
	}

	it('drains, records the result, and releases the lease on the happy path', async () => {
		const client = happyClient();
		const { sqs } = fakeSqs([[]]);

		const result = await runMonitoredSesInboundWake({
			wakeCorrelationId: 'wake-2',
			client,
			sqs,
			fetchObject
		});

		expect(result.outcome).toBe('idle');
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
			insertCallbackEvent: vi.fn(async () => ({ data: null, error: { message: 'boom' } })),
			insertAttachments: vi.fn()
		} as unknown as SesInboundWorkerClient;
		const { sqs } = fakeSqs([[validMessage]]);

		await expect(
			runMonitoredSesInboundWake({ wakeCorrelationId: 'wake-3', client, sqs, fetchObject })
		).rejects.toThrow(/boom/);
		expect(rpc).toHaveBeenCalledWith(
			'record_communication_worker_wake_result',
			expect.objectContaining({ p_route_outcome: 'error' })
		);
	});

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

		await runMonitoredSesInboundWake({
			wakeCorrelationId: 'wake-dlq-1',
			client: happyClient(),
			sqs,
			fetchObject,
			dlq: fakeDlq(2),
			owner
		});

		expect(raiseOwnerAlert).toHaveBeenCalledTimes(1);
		expect(raiseOwnerAlert).toHaveBeenCalledWith(
			owner,
			expect.objectContaining({ kind: 'ses_inbound_dlq_message', severity: 'urgent' })
		);
	});

	it('does not alert again while an unread alert from the last day still stands', async () => {
		raiseOwnerAlert.mockClear();
		const { sqs } = fakeSqs([[]]);
		const owner = fakeOwner([{ id: 'existing-notification' }]);

		await runMonitoredSesInboundWake({
			wakeCorrelationId: 'wake-dlq-2',
			client: happyClient(),
			sqs,
			fetchObject,
			dlq: fakeDlq(2),
			owner
		});

		expect(raiseOwnerAlert).not.toHaveBeenCalled();
	});
});
